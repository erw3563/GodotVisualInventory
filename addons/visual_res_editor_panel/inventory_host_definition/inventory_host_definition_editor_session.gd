@tool
extends RefCounted
## 窗口会话同时持有两栏草稿；一次准备、一次校验、一次撤销操作。
const Catalog = preload("res://addons/visual_res_editor_panel/inventory_host_definition/inventory_host_layout_editor_catalog.gd")
const FeatureCatalog = preload("res://addons/visual_res_editor_panel/inventory_host_definition/inventory_host_feature_catalog.gd")
const AdditionPlanner = preload("res://addons/visual_res_editor_panel/inventory_host_definition/inventory_host_feature_addition_planner.gd")
const Graph = preload("res://addons/visual_res_editor_panel/inventory_host_definition/host_editor_resource_graph.gd")
signal changed
signal structure_changed
var target: InventoryHostDefinition
var draft: InventoryPanelAssemblyDefinition
var layout_reference: InventoryPanelAssemblyDefinition
var edit_reference := false
var undo_manager: EditorUndoRedoManager
var baseline_layout: InventoryPanelAssemblyDefinition
var baseline := ""
var reference_baseline := ""
var draft_baseline := ""
var drafts: Dictionary = {}
var replacement := false
var feature_catalog := FeatureCatalog.new()
var entries: Array[Dictionary] = []
var selected := -1
var reverse: Dictionary = {}
var features_baseline := ""
var entries_baseline := ""

func setup(resource: InventoryHostDefinition, manager: EditorUndoRedoManager) -> void:
	target = resource
	undo_manager = manager
	feature_catalog.refresh()
	reload()

func reload() -> void:
	_load_target()

func _load_target(continuation: Dictionary = {}, continue_layout := false) -> void:
	_clear_appearance_views()
	reverse.clear()
	var originals: Dictionary = {}
	baseline_layout = target.layout
	baseline = Graph.stamp(target.layout, true)
	layout_reference = target.layout
	reference_baseline = baseline
	draft = Graph.copy(target.layout, originals, reverse)
	draft_baseline = Graph.stamp(draft)
	edit_reference = continue_layout
	replacement = false
	drafts.clear()
	entries.clear()
	var appearance_views := {}
	for feature in target.features:
		var entry := {"draft": Graph.copy(feature, originals, reverse), "reference": feature, "editable": false, "view": {}}
		if continuation.has(feature) and not continuation[feature].is_empty():
			var previous: Dictionary = continuation[feature].pop_front()
			entry.editable = previous.editable
			entry.view = previous.view
			if not previous.appearance.is_empty():
				appearance_views[str(entry.draft.get_instance_id())] = previous.appearance
		entries.append(entry)
	if not appearance_views.is_empty():
		set_meta("appearance_views", appearance_views)
	features_baseline = Graph.stamp(target.features, true)
	entries_baseline = _entries_stamp()
	selected = clampi(selected, 0, entries.size() - 1) if not entries.is_empty() else -1
	structure_changed.emit()
	changed.emit()

func select_type(index: int) -> void:
	if index < 0 or index >= Catalog.types().size():
		return
	var old_index := Catalog.type_index(draft)
	if old_index == index:
		return
	if old_index >= 0:
		drafts[old_index] = draft
	draft = drafts.get(index)
	if draft == null:
		draft = Catalog.types()[index].new()
	layout_reference = null
	edit_reference = false
	replacement = true
	changed.emit()

func use_reference(resource: Resource) -> bool:
	if not resource is InventoryPanelAssemblyDefinition or not resource.get_script().can_instantiate():
		return false
	layout_reference = resource
	reference_baseline = Graph.stamp(resource, true)
	draft = Graph.copy(resource, {}, reverse)
	draft_baseline = Graph.stamp(draft)
	edit_reference = false
	replacement = layout_reference != target.layout
	changed.emit()
	return true

func make_unique() -> void:
	if draft == null:
		return
	draft = Graph.copy(draft)
	layout_reference = null
	edit_reference = false
	replacement = true
	changed.emit()

func enable_reference_edit() -> void:
	if layout_reference != null:
		edit_reference = true
		changed.emit()

func can_edit() -> bool:
	return draft != null and (layout_reference == null or edit_reference)

func layout_dirty() -> bool:
	return replacement or Graph.stamp(draft) != draft_baseline

func features_dirty() -> bool:
	return _entries_stamp() != entries_baseline

func is_dirty() -> bool:
	return layout_dirty() or features_dirty()

func _entries_stamp() -> String:
	var parts: Array = []
	for entry in entries:
		parts.append([entry.reference.get_instance_id() if entry.reference != null else 0, entry.draft])
	return Graph.stamp(parts)

func has_conflict() -> bool:
	if layout_dirty() and (target.layout != baseline_layout or Graph.stamp(target.layout, true) != baseline or (layout_reference != null and Graph.stamp(layout_reference, true) != reference_baseline)):
		return true
	return features_dirty() and Graph.stamp(target.features, true) != features_baseline

func set_field(key: StringName, value: Variant) -> void:
	if can_edit() and key in Catalog.fields(draft):
		if value is StyleBox or value is Material:
			value = Graph.copy(value)
		draft.set(key, value)
		draft.emit_changed()
		changed.emit()

## 嵌套样式与材质等就地修改后刷新脏标记与预览。
func touch_layout() -> void:
	if can_edit() and draft != null:
		draft.emit_changed()
		changed.emit()

func feature_drafts() -> Array[InventoryHostFeatureDefinition]:
	var result: Array[InventoryHostFeatureDefinition] = []
	for entry in entries:
		result.append(entry.draft)
	return result

func preview_feature_addition(type: Script) -> Dictionary:
	var result := AdditionPlanner.new().prepare(feature_catalog, entries, type, selected, draft)
	result["baseline"] = _addition_stamp()
	return result

func _addition_stamp() -> String:
	var catalog_data: Array = []
	for entry in feature_catalog.entries:
		catalog_data.append([entry.type, entry.get("required_features", []), entry.get("role_titles", {}), entry.get("adapter"), entry.get("path", "")])
	var entry_data: Array = []
	for entry in entries:
		entry_data.append([entry.draft, entry.reference, entry.editable])
	return Graph.stamp([entry_data, catalog_data, feature_catalog.errors, draft, selected], true)

func commit_feature_addition(preview: Dictionary) -> Dictionary:
	var result := preview.duplicate()
	if not result.ok:
		return result
	if result.get("baseline", "") != _addition_stamp():
		result.ok = false
		result.error_code = &"feature_addition_preview_stale"
		return result
	entries = result.entries
	result.erase("entries")
	selected = result.selected_index
	structure_changed.emit()
	changed.emit()
	return result

func select_feature(index: int) -> void:
	selected = index if index >= 0 and index < entries.size() else -1
	structure_changed.emit()

func remove_feature(index: int) -> void:
	if index < 0 or index >= entries.size():
		return
	entries.remove_at(index)
	selected = mini(index, entries.size() - 1)
	structure_changed.emit()
	changed.emit()

func move_feature(index: int, offset: int) -> void:
	var next := index + offset
	if index < 0 or index >= entries.size() or next < 0 or next >= entries.size():
		return
	var entry := entries[index]
	entries.remove_at(index)
	entries.insert(next, entry)
	selected = next
	structure_changed.emit()
	changed.emit()

func edit_feature_reference(index: int) -> void:
	if index >= 0 and index < entries.size():
		entries[index].editable = true
		structure_changed.emit()

func unique_feature(index: int) -> void:
	if index < 0 or index >= entries.size() or entries[index].draft == null:
		return
	var previous: Resource = entries[index].draft
	entries[index].draft = Graph.copy(previous)
	var views: Dictionary = get_meta("appearance_views", {})
	var token := str(previous.get_instance_id())
	if views.has(token):
		var view: Dictionary = views[token]
		view.get("types", {}).clear()
		views.erase(token)
		views[str(entries[index].draft.get_instance_id())] = view
	entries[index].reference = null
	entries[index].editable = true
	feature_view(index)["unique"] = true
	structure_changed.emit()
	changed.emit()

func feature_editable(index: int) -> bool:
	return index >= 0 and index < entries.size() and entries[index].editable and entries[index].draft != null and not feature_catalog.find(entries[index].draft.get_script()).is_empty()

func feature_view(index: int) -> Dictionary:
	if not entries[index].has("view"):
		entries[index].view = {}
	return entries[index].view

func touch_feature(index: int) -> void:
	if feature_editable(index):
		entries[index].draft.emit_changed()
		changed.emit()

func diagnostics() -> Array[Dictionary]:
	var current_layout: Resource = draft if layout_dirty() else target.layout
	var current_features: Array[InventoryHostFeatureDefinition] = feature_drafts() if features_dirty() else target.features
	return feature_catalog.diagnose(current_layout, current_features)

func validation_error() -> String:
	if has_conflict():
		return "待提交配置已被外部修改，请重新载入以避免覆盖。"
	var problem := Catalog.validate(draft if layout_dirty() else target.layout)
	if not problem.is_empty():
		return problem
	if features_dirty() and not feature_catalog.errors.is_empty():
		return "\n".join(feature_catalog.errors)
	for item in diagnostics():
		if item.has("error"):
			return "功能 %d：%s" % [item.index + 1, item.error]
	return ""

func apply() -> String:
	var problem := validation_error()
	if not problem.is_empty():
		return problem
	if not is_dirty():
		return ""
	if undo_manager == null:
		return "编辑器撤销管理器不可用。"
	var patches: Array = []
	var cache: Dictionary = {}
	if layout_dirty():
		var next_layout: Resource
		if layout_reference != null and not edit_reference:
			next_layout = layout_reference
		else:
			next_layout = Graph.prepare(draft, reverse if edit_reference else {}, patches, cache)
		if next_layout != target.layout:
			patches.append([target, &"layout", next_layout, target.layout])
	if features_dirty():
		var next_features: Array[InventoryHostFeatureDefinition] = []
		for entry in entries:
			if entry.reference != null and not entry.editable:
				next_features.append(entry.reference)
			else:
				next_features.append(Graph.prepare(entry.draft, reverse if entry.reference != null else {}, patches, cache))
		patches.append([target, &"features", next_features, target.features.duplicate()])
	if patches.is_empty():
		_continue_after_apply(cache)
		return ""
	# 共享字段的各份草稿在提交前校验写入值的一致性。
	var writes: Dictionary = {}
	for patch in patches:
		var key := str(patch[0].get_instance_id()) + ":" + str(patch[1])
		if writes.has(key) and Graph.stamp(writes[key], true) != Graph.stamp(patch[2], true):
			return "同一共享资源有冲突的草稿修改，请重新载入。"
		writes[key] = patch[2]
	var context: Resource = layout_reference if layout_dirty() and not features_dirty() and edit_reference else target
	undo_manager.create_action("编辑库存 Host 配置", UndoRedo.MERGE_DISABLE, context)
	var notified: Dictionary = {}
	for patch in patches:
		undo_manager.add_do_property(patch[0], patch[1], patch[2])
		undo_manager.add_undo_property(patch[0], patch[1], patch[3])
		notified[patch[0]] = true
	notified[target] = true
	for resource in notified:
		undo_manager.add_do_method(resource, "emit_changed")
		undo_manager.add_undo_method(resource, "emit_changed")
	undo_manager.commit_action()
	_continue_after_apply(cache)
	return ""

## 按提交后的资源身份恢复会话权限与视图，并刷新隔离草稿和冲突基准。
func _continue_after_apply(committed: Dictionary) -> void:
	var continuation := {}
	var views: Dictionary = get_meta("appearance_views", {})
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var reference: Resource = committed.get(entry.draft, entry.reference)
		if reference == null:
			continue
		var view := feature_view(index)
		if entry.reference == null:
			view["unique"] = true
		if not continuation.has(reference):
			continuation[reference] = []
		continuation[reference].append({"editable": entry.editable, "view": view, "appearance": views.get(str(entry.draft.get_instance_id()), {})})
	var continue_layout: bool = can_edit() and committed.get(draft, layout_reference) == target.layout
	_load_target(continuation, continue_layout)

func _clear_appearance_views() -> void:
	for view in get_meta("appearance_views", {}).values():
		if view.has("types"):
			view.types.clear()
	if has_meta("appearance_views"):
		remove_meta("appearance_views")
