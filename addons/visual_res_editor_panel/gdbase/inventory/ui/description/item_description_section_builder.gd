class_name ItemDescriptionSectionBuilder
extends RefCounted
## UI 层的物品描述段落组装器。按模板 Part 顺序配对当前实例 State。

const BASE_SECTION_TYPE := "Base"


## 按 ItemData.parts 顺序构建 {section_type, controls} 描述段落。
static func build(item_instance: ItemInstanceData) -> Array[Dictionary]:
	var sections: Array[Dictionary] = []
	if item_instance == null or item_instance.item_data == null:
		return sections
	var item_data := item_instance.item_data
	var shape_state := item_instance.get_shape_state()
	var shape_displayed := false
	for part in item_data.parts:
		if part == null:
			continue
		var state: ItemInstanceState
		if part is ItemShapePart:
			state = shape_state
			shape_displayed = true
		var state_key := part.get_instance_state_key()
		if not part is ItemShapePart and !state_key.is_empty():
			state = item_instance.get_state_by_key(state_key)
		var controls := _build_controls(item_instance, part, state)
		if controls.is_empty():
			continue
		sections.append({
			"section_type": item_data._get_part_type(part),
			"controls": controls,
		})
	if shape_state != null and not shape_displayed:
		sections.append({
			"section_type": ItemShapeState.SHAPE_STATE_KEY,
			"controls": shape_state.get_description_panel_for_cells(item_instance.get_local_cells(), item_instance.dir),
		})
	return sections


## 动态 Part 显示当前 State；静态 Part 显示模板配置。
static func _build_controls(
	item_instance: ItemInstanceData,
	part: ItemPart,
	state: ItemInstanceState
) -> Array[Control]:
	if state is ItemShapeState:
		return (state as ItemShapeState).get_description_panel_for_cells(
			item_instance.get_local_cells(), item_instance.dir
		)
	if part is ItemShapePart:
		return [ItemShapeDescriptionControl.create(item_instance.get_local_cells(), item_instance.dir)]
	if state != null:
		return state.get_description_panel_with_part(part)
	var controls: Array[Control] = []
	var part_controls = part.get_description_panel()
	if part_controls == null:
		return controls
	for control in part_controls:
		if control is Control:
			controls.append(control)
	return controls
