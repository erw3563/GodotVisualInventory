@tool
extends RefCounted
## ItemData 草稿；共享 Part 需显式授权，取消始终不回写。
const Graph = preload("res://addons/visual_res_editor_panel/inventory_host_definition/host_editor_resource_graph.gd")
signal changed
signal structure_changed
var target: ItemData
var draft: ItemData
var undo_manager: EditorUndoRedoManager
var entries: Array[Dictionary] = []
var reverse: Dictionary = {}
var baseline := ""
var draft_baseline := ""

func setup(value: ItemData, manager: EditorUndoRedoManager = null) -> void:
	target = value
	undo_manager = manager
	reload()

func reload() -> void:
	_clear_appearance_views()
	reverse.clear()
	draft = Graph.copy(target, {}, reverse)
	baseline = Graph.stamp(target, true)
	draft_baseline = Graph.stamp(draft)
	_rebuild_entries()
	structure_changed.emit()
	changed.emit()

func _rebuild_entries() -> void:
	entries = [{"draft": draft, "editable": true, "reference": null}]
	for part in draft.parts:
		var source: Resource = reverse.get(part) if reverse.has(part) else null
		entries.append({"draft": part, "editable": source == null, "reference": source})

func feature_editable(index: int) -> bool:
	return index >= 0 and index < entries.size() and entries[index].editable

func touch_feature(_index: int) -> void:
	changed.emit()

func edit_shared(index: int) -> void:
	if index > 0 and index < entries.size():
		entries[index].editable = true
		structure_changed.emit()

func make_unique(index: int) -> void:
	if index <= 0 or index >= entries.size():
		return
	draft.parts[index - 1] = Graph.copy(draft.parts[index - 1])
	_rebuild_entries()
	structure_changed.emit()
	changed.emit()

func add_part(type: Script) -> bool:
	if type == null or type.is_abstract() or not type.can_instantiate():
		return false
	var part: Resource = type.new()
	if not part is ItemPart:
		return false
	draft.try_add_part(part)
	if part not in draft.parts:
		return false
	_rebuild_entries()
	structure_changed.emit()
	changed.emit()
	return true

func remove_part(index: int) -> void:
	if index <= 0 or index >= entries.size():
		return
	draft.parts.remove_at(index - 1)
	_rebuild_entries()
	structure_changed.emit()
	changed.emit()

func move_part(index: int, step: int) -> void:
	var next := index + step
	if index <= 0 or next <= 0 or index >= entries.size() or next >= entries.size():
		return
	var part := draft.parts[index - 1]
	draft.parts.remove_at(index - 1)
	draft.parts.insert(next - 1, part)
	_rebuild_entries()
	structure_changed.emit()
	changed.emit()

func set_tag(tag: String, enabled: bool) -> void:
	tag = tag.strip_edges()
	if tag.is_empty():
		return
	var part := draft.get_type_part(ItemTagPart.get_part_type()) as ItemTagPart
	if part == null or not feature_editable(draft.parts.find(part) + 1):
		return
	var tags := part.tags.duplicate()
	while tag in tags:
		tags.remove_at(tags.find(tag))
	if enabled:
		tags.append(tag)
	part.tags = tags
	structure_changed.emit()
	changed.emit()

func tags() -> PackedStringArray:
	var part := draft.get_type_part(ItemTagPart.get_part_type()) as ItemTagPart
	return part.tags.duplicate() if part != null else PackedStringArray()

func is_dirty() -> bool:
	return Graph.stamp(draft) != draft_baseline

func validate() -> String:
	if draft.max_num < 1:
		return "最大堆叠数必须至少为 1"
	var types: Dictionary = {}
	var keys: Dictionary = {}
	for part in draft.parts:
		if part == null:
			return "存在空功能，请移除或配置"
		var type: String = part.get_script().get_part_type()
		if types.has(type) and (not part.allows_multiple() or not types[type].allows_multiple()):
			return "重复的单例功能：" + type
		types[type] = part
		var key := part.get_instance_state_key()
		if not key.is_empty():
			if keys.has(key):
				return "重复的实例状态键：" + key
			keys[key] = true
		if part.has_method("validate_configuration"):
			var configuration_reason: String = str(part.call("validate_configuration"))
			if not configuration_reason.is_empty():
				return type + "：" + configuration_reason
		if part is ItemTagPart:
			var seen := {}
			for tag in part.tags:
				if tag.strip_edges().is_empty() or seen.has(tag):
					return "标签不能为空或重复"
				seen[tag] = true
	return ""

func apply() -> String:
	var reason := validate()
	if not reason.is_empty():
		return reason
	if Graph.stamp(target, true) != baseline:
		return "原物品或共享引用已被外部修改，请重新载入后编辑"
	if not is_dirty():
		_clear_appearance_views()
		return ""
	var patches: Array = []
	Graph.prepare(draft, reverse, patches, {})
	if undo_manager != null:
		undo_manager.create_action("编辑物品", UndoRedo.MERGE_DISABLE, target)
		for patch in patches:
			undo_manager.add_do_property(patch[0], patch[1], patch[2])
			undo_manager.add_undo_property(patch[0], patch[1], patch[3])
		undo_manager.add_do_method(target, "emit_changed")
		undo_manager.add_undo_method(target, "emit_changed")
		undo_manager.commit_action()
	else:
		for patch in patches:
			patch[0].set(patch[1], patch[2])
		target.emit_changed()
	reload()
	return ""

func save_as(path: String) -> String:
	var reason := validate()
	if not reason.is_empty():
		return reason
	if not path.begins_with("res://") or path.get_extension() != "tres":
		return "请选择项目内的 .tres 文件"
	var copy: ItemData = Graph.copy(draft)
	var error := ResourceSaver.save(copy, path)
	return "" if error == OK else "保存失败：" + error_string(error)

func _clear_appearance_views() -> void:
	for view in get_meta("appearance_views", {}).values():
		if view.has("types"):
			view.types.clear()
	if has_meta("appearance_views"):
		remove_meta("appearance_views")
