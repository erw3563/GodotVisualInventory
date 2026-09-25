class_name ItemAnimationProcessor
extends InventoryItemPresentation
## 被动播放器：仅保存弱实例的目标外观与本次播放目标，不订阅业务事件。
signal playback_started(item: ItemInstanceData, animation_key: StringName, handle: ItemAnimationPlaybackHandle)
var view_provider: InventoryItemViewProvider
var _appearances: Dictionary = {}
var _active: Dictionary = {}
var _sustained: Dictionary = {}
var _disposing := false
var _next_appearance_generation := 0

func _ready() -> void:
	set_process(false)

func has_animation(item: ItemInstanceData, key: StringName) -> bool:
	var part := _get_part(item)
	return part != null and part.get_animation(key) != null

func has_appearance(item: ItemInstanceData, key: StringName) -> bool:
	var part := _get_part(item)
	return part != null and part.get_appearance(key) != null

func play(item: ItemInstanceData, animation_key: StringName, options: Dictionary = {}) -> ItemAnimationPlaybackHandle:
	var part := _get_part(item)
	if part == null:
		return _ended(ItemAnimationPlaybackHandle.Status.SKIPPED, &"animation_not_configured")
	var definition := part.get_animation(animation_key)
	var target: StringName = definition.target_appearance_key if definition != null else &""
	return _play(item, animation_key, target, options)

func transition_to(item: ItemInstanceData, appearance_key: StringName, animation_key: StringName, options: Dictionary = {}) -> ItemAnimationPlaybackHandle:
	return _play(item, animation_key, appearance_key, options, true)

func set_appearance(item: ItemInstanceData, appearance_key: StringName) -> Dictionary:
	var reason := _validate_appearance(item, appearance_key)
	if not reason.is_empty():
		return {"success": false, "reason_key": reason}
	_record_target(item, appearance_key)
	_sync_current_views(item)
	return {"success": true, "reason_key": &""}

func reset_appearance(item: ItemInstanceData) -> Dictionary:
	var part := _get_part(item)
	if part == null:
		return {"success": false, "reason_key": &"animation_not_configured"}
	if not part.default_appearance_key.is_empty():
		var reason := _validate_appearance(item, part.default_appearance_key)
		if not reason.is_empty():
			return {"success": false, "reason_key": reason}
	_appearances.erase(item.get_instance_id())
	_stop_channel(item, ItemAnimationContent.Channel.APPEARANCE)
	_sync_current_views(item)
	return {"success": true, "reason_key": &""}

func _get_appearance(item: ItemInstanceData) -> ItemAppearanceDefinition:
	var part := _get_part(item)
	if part == null:
		return null
	var record: Dictionary = _appearances.get(item.get_instance_id(), {})
	var key: StringName = record.key if not record.is_empty() and record.item.get_ref() == item else part.default_appearance_key
	return part.get_appearance(key) if not key.is_empty() else null

func get_appearance_texture(item: ItemInstanceData) -> Texture2D:
	var appearance := _get_appearance(item)
	if appearance == null or not appearance.validate_configuration().is_empty():
		return null
	return appearance.loop_animation.frames[0] if appearance.loop_animation != null else appearance.texture

func get_appearance_generation(item: ItemInstanceData) -> int:
	if item == null:
		return -1
	var record: Dictionary = _appearances.get(item.get_instance_id(), {})
	return int(record.get("generation", -1)) if not record.is_empty() and record.item.get_ref() == item else -1

func sync_view(item: ItemInstanceData, view: ItemIconView) -> void:
	if _disposing or Engine.is_editor_hint() or not is_instance_valid(view) or view.get_bound_item() != item or not view.is_inside_tree() or not view.is_visible_in_tree() or view.is_queued_for_deletion():
		return
	var appearance := _get_appearance(item)
	var view_id := view.get_instance_id()
	if appearance != null and not appearance.validate_configuration().is_empty():
		return
	var prior: Dictionary = _sustained.get(view_id, {})
	if not prior.is_empty() and prior.item.get_ref() == item and prior.generation == view.binding_generation and prior.appearance == appearance:
		view.set_appearance_texture(get_appearance_texture(item), prior.token.get_instance_id())
		return
	_end_sustained(view_id)
	if appearance == null:
		return
	var token := RefCounted.new()
	var owner_id := token.get_instance_id()
	var callback := func() -> void: _end_sustained(view_id, owner_id)
	var execution := appearance.loop_animation.create_execution(true) if appearance.loop_animation != null else null
	_sustained[view_id] = {"view": weakref(view), "item": weakref(item), "generation": view.binding_generation,
		"appearance": appearance, "execution": execution, "token": token, "callback": callback}
	view.playback_invalidated.connect(callback)
	view.set_appearance_texture(get_appearance_texture(item), owner_id)
	if execution != null:
		view.set_sustained_frame(owner_id, execution.advance(0.0).get("texture"))
	_update_processing()

func _end_sustained(view_id: int, owner_id := 0) -> void:
	var record: Dictionary = _sustained.get(view_id, {})
	if record.is_empty() or (owner_id != 0 and record.token.get_instance_id() != owner_id):
		return
	_sustained.erase(view_id)
	var view := record.view.get_ref() as ItemIconView
	if is_instance_valid(view):
		if view.playback_invalidated.is_connected(record.callback):
			view.playback_invalidated.disconnect(record.callback)
		view.clear_sustained_frame(record.token.get_instance_id())
		view.clear_appearance(record.token.get_instance_id())
	_update_processing()

func _advance_sustained(delta: float) -> void:
	for view_id in _sustained.keys():
		var record: Dictionary = _sustained[view_id]
		var view := record.view.get_ref() as ItemIconView
		var item := record.item.get_ref() as ItemInstanceData
		if item == null or not is_instance_valid(view) or view.is_queued_for_deletion() or not view.is_inside_tree() or not view.is_visible_in_tree() or view.binding_generation != record.generation or view.get_bound_item() != item:
			_end_sustained(view_id)
			continue
		var execution := record.execution as ItemAnimationExecution
		if execution != null and not view.has_temporary_frame():
			view.set_sustained_frame(record.token.get_instance_id(), execution.advance(delta).get("texture"))

func _update_processing() -> void:
	var running := not _active.is_empty()
	for record in _sustained.values():
		if record.execution != null:
			running = true
			break
	set_process(running and not _disposing)

func _play(item: ItemInstanceData, key: StringName, target: StringName, options: Dictionary, explicit_target := false) -> ItemAnimationPlaybackHandle:
	var part := _get_part(item)
	if part == null:
		return _ended(ItemAnimationPlaybackHandle.Status.SKIPPED, &"animation_not_configured")
	var definition := part.get_animation(key)
	# play 的忽略策略连同默认外观一起忽略；显式 transition 的业务目标始终接受。
	if not explicit_target and definition != null and definition.content != null and options.get("conflict", &"replace") == &"ignore" and _has_channel(item, definition.content.get_channel()):
		return _ended(ItemAnimationPlaybackHandle.Status.IGNORED, &"channel_busy")
	if explicit_target or not target.is_empty():
		var reason := _validate_appearance(item, target)
		if not reason.is_empty():
			return _ended(ItemAnimationPlaybackHandle.Status.REJECTED, reason)
		_record_target(item, target)
	var views: Array[ItemIconView] = view_provider.find_item_views(item) if view_provider != null else []
	for view in views:
		sync_view(item, view)
	var reason := part.validate_configuration()
	if definition == null:
		reason = &"unknown_animation_key"
	if not reason.is_empty():
		return _ended(ItemAnimationPlaybackHandle.Status.REJECTED, reason)
	if view_provider == null:
		return _ended(ItemAnimationPlaybackHandle.Status.REJECTED, &"missing_view_provider")
	var channel := definition.content.get_channel()
	if channel not in ItemAnimationContent.Channel.values() or not is_finite(definition.content.get_duration()) or definition.content.get_duration() <= 0.0:
		return _ended(ItemAnimationPlaybackHandle.Status.REJECTED, &"invalid_animation_content")
	if options.get("conflict", &"replace") == &"ignore" and _has_channel(item, channel):
		return _ended(ItemAnimationPlaybackHandle.Status.IGNORED, &"channel_busy")
	_stop_channel(item, channel)
	if views.is_empty():
		return _ended(ItemAnimationPlaybackHandle.Status.SKIPPED, &"no_visible_views")
	var handle := ItemAnimationPlaybackHandle.new()
	var id := handle.get_instance_id()
	var record := {"handle": handle, "item": weakref(item), "channel": channel, "targets": {}}
	_active[id] = record
	handle._command = _end_handle.bind(id)
	for view in views:
		if not is_instance_valid(view) or view.get_bound_item() != item or not view.is_visible_in_tree():
			continue
		var view_id := view.get_instance_id()
		if record.targets.has(view_id):
			continue
		# 每个通道拥有独立 Callable；同一信号不能仅靠 bound 参数区分连接。
		var callback := func() -> void: _on_target_invalidated(id, view_id)
		record.targets[view_id] = {"view": weakref(view), "generation": view.binding_generation,
			"execution": definition.content.create_execution(), "callback": callback}
		view.playback_invalidated.connect(callback)
		_apply_sample(view, channel, id, record.targets[view_id].execution.advance(0.0))
	if record.targets.is_empty():
		_end_handle(ItemAnimationPlaybackHandle.Status.SKIPPED, &"no_visible_views", id)
	else:
		set_process(true)
		playback_started.emit(item, key, handle)
	return handle

func _process(delta: float) -> void:
	_advance_sustained(delta)
	for id in _active.keys():
		if not _active.has(id):
			continue
		var record: Dictionary = _active[id]
		var item := record.item.get_ref() as ItemInstanceData
		for view_id in record.targets.keys():
			if not _active.has(id) or not record.targets.has(view_id):
				continue
			var target: Dictionary = record.targets[view_id]
			var view := target.view.get_ref() as ItemIconView
			if item == null or not is_instance_valid(view) or view.is_queued_for_deletion() or not view.is_inside_tree() or not view.is_visible_in_tree() or view.binding_generation != target.generation or view.get_bound_item() != item:
				_on_target_invalidated(id, view_id)
				continue
			var execution := target.execution as ItemAnimationExecution
			_apply_sample(view, record.channel, id, execution.advance(delta))
			if execution.is_finished():
				_end_target(id, view_id, &"completed")
		if _active.has(id) and record.targets.is_empty():
			_end_handle(ItemAnimationPlaybackHandle.Status.COMPLETED, &"", id)
	_purge_dead_items()
	_update_processing()

func _apply_sample(view: ItemIconView, channel: int, id: int, sample: Dictionary) -> void:
	match channel:
		ItemAnimationContent.Channel.APPEARANCE:
			view.set_frame(id, sample.get("texture") as Texture2D)
		ItemAnimationContent.Channel.FEEDBACK:
			view.set_feedback_rotation(id, float(sample.get("rotation", 0.0)))

func _on_target_invalidated(id: int, view_id: int) -> void:
	_end_target(id, view_id, &"view_unavailable")
	if _active.has(id) and _active[id].targets.is_empty():
		_end_handle(ItemAnimationPlaybackHandle.Status.SKIPPED, &"all_views_unavailable", id)

func _end_target(id: int, view_id: int, reason: StringName) -> void:
	if not _active.has(id):
		return
	var record: Dictionary = _active[id]
	if not record.targets.has(view_id):
		return
	var target: Dictionary = record.targets[view_id]
	record.targets.erase(view_id)
	var view := target.view.get_ref() as ItemIconView
	if is_instance_valid(view):
		if view.playback_invalidated.is_connected(target.callback):
			view.playback_invalidated.disconnect(target.callback)
		if view.binding_generation == target.generation and view.get_bound_item() == record.item.get_ref():
			view.clear_frame(id)
			view.clear_feedback(id)
	record.handle.child_results.append({"view_id": view_id, "reason_key": reason})

func _end_handle(status: ItemAnimationPlaybackHandle.Status, reason: StringName, id: int) -> void:
	if not _active.has(id):
		return
	var record: Dictionary = _active[id]
	for view_id in record.targets.keys():
		_end_target(id, view_id, reason)
	_active.erase(id)
	record.handle.settle(status, reason)
	_update_processing()

func _has_channel(item: ItemInstanceData, channel: int) -> bool:
	for record in _active.values():
		if record.item.get_ref() == item and record.channel == channel:
			return true
	return false

func _stop_channel(item: ItemInstanceData, channel: int) -> void:
	for id in _active.keys():
		if not _active.has(id):
			continue
		var record: Dictionary = _active[id]
		if record.item.get_ref() == item and record.channel == channel:
			_end_handle(ItemAnimationPlaybackHandle.Status.REPLACED, &"replaced", id)

func _record_target(item: ItemInstanceData, key: StringName) -> void:
	_purge_dead_items()
	_next_appearance_generation += 1
	_appearances[item.get_instance_id()] = {"item": weakref(item), "key": key, "generation": _next_appearance_generation}
	_stop_channel(item, ItemAnimationContent.Channel.APPEARANCE)

func _sync_current_views(item: ItemInstanceData) -> void:
	if view_provider == null:
		return
	for view in view_provider.find_item_views(item):
		sync_view(item, view)

func _validate_appearance(item: ItemInstanceData, key: StringName) -> StringName:
	var part := _get_part(item)
	if part == null:
		return &"animation_not_configured"
	var keys := {}
	for appearance in part.appearances:
		if appearance == null:
			return &"null_appearance"
		var reason := appearance.validate_configuration()
		if not reason.is_empty():
			return reason
		if keys.has(appearance.key):
			return &"duplicate_appearance_key"
		keys[appearance.key] = true
	return &"" if keys.has(key) else &"unknown_appearance_key"

func _get_part(item: ItemInstanceData) -> ItemAnimationPart:
	if item == null or item.item_data == null:
		return null
	for part in item.item_data.parts:
		if part is ItemAnimationPart:
			return part
	return null

func _ended(status: ItemAnimationPlaybackHandle.Status, reason: StringName) -> ItemAnimationPlaybackHandle:
	var handle := ItemAnimationPlaybackHandle.new()
	handle.settle(status, reason)
	return handle

func _purge_dead_items() -> void:
	for id in _appearances.keys():
		if _appearances[id].item.get_ref() == null:
			_appearances.erase(id)

func _exit_tree() -> void:
	_disposing = true
	for view_id in _sustained.keys():
		_end_sustained(view_id)
	for id in _active.keys():
		_end_handle(ItemAnimationPlaybackHandle.Status.CANCELLED, &"service_disposed", id)
	_appearances.clear()
