@tool
class_name ItemReactionReshapeAction
extends ItemReactionAction
## ItemReactionReshapeAction 将源物品提交为下一份轮廓。
## 形状更新：按 shape_stages 依次提交；列表用尽后不再变形。
## 规则改变：将 rule_shape 当作扩展核，对当前轮廓的每一格做扩展检测。

## 变形所使用的模式。
enum ReshapeMode {
	SHAPE_UPDATE, ## 形状更新
	RULE_CHANGE, ## 规则改变
}

## 当前变形模式。
@export var reshape_mode: ReshapeMode = ReshapeMode.SHAPE_UPDATE:
	set(value):
		reshape_mode = value
		notify_property_list_changed()
## 形状更新模式下按阶段提交的轮廓列表；第 0 回合仍用形状拼图，第一次成功后取本列表第 0 项。
@export var shape_stages: Array[Shape] = []
## 规则改变模式的扩展核。例如十字会对当前每一格检测其上、下、左、右邻格。
@export var rule_shape: Shape

## 按当前模式隐藏无关导出字段。
func _validate_property(property: Dictionary) -> void:
	match property.name:
		"shape_stages":
			if reshape_mode != ReshapeMode.SHAPE_UPDATE:
				property.usage = property.usage & ~PROPERTY_USAGE_EDITOR
		"rule_shape":
			if reshape_mode != ReshapeMode.RULE_CHANGE:
				property.usage = property.usage & ~PROPERTY_USAGE_EDITOR

## 尝试将源物品变形为下一份轮廓。
func validate_configuration() -> StringName:
	if reshape_mode == ReshapeMode.SHAPE_UPDATE:
		if shape_stages.is_empty() or shape_stages.has(null):
			return &"invalid_reshape_stages"
	elif reshape_mode == ReshapeMode.RULE_CHANGE:
		if rule_shape == null or rule_shape.get_cells().is_empty():
			return &"invalid_reshape_rule"
	else:
		return &"invalid_reshape_mode"
	return &""

func plan(context: ItemReactionPlanContext) -> ItemReactionPlanResult:
	if not context.view.is_spatial() or not context.view.has_item(context.source):
		return ItemReactionPlanResult.failed(&"reshape_source_unavailable")
	var source_item_instance_data := context.view.get_item(context.source)
	var next_shape := _build_next_shape(context.view, source_item_instance_data, context.source)
	if next_shape == null:
		return ItemReactionPlanResult.failed(&"reshape_unchanged")
	var reason := ItemReshapeProcessor.validate_target(source_item_instance_data, next_shape)
	if reason != &"":
		return ItemReactionPlanResult.failed(reason)
	var prepared := ItemReshapeProcessor.prepare_state(source_item_instance_data, next_shape, true)
	return context.append(InventoryOperationRequest.Type.RESHAPE, context.source, -1, Vector2i(-1, -1), prepared)

## 按当前模式算出下一份轮廓；无法继续变形时返回 null。
func _build_next_shape(
	view: InventoryOperationView,
	source_item_instance_data: ItemInstanceData,
	source_identity: ItemInstanceData
) -> Shape:
	if reshape_mode == ReshapeMode.RULE_CHANGE:
		return _build_rule_expanded_shape(view, source_item_instance_data, source_identity)
	return _build_sequence_next_shape(source_item_instance_data)

## 形状更新：按阶段列表提交下一份轮廓；超出列表后停止。
func _build_sequence_next_shape(source_item_instance_data: ItemInstanceData) -> Shape:
	var state := source_item_instance_data.get_shape_state()
	var current_stage := state.shape_stage if state != null else 0
	if current_stage >= shape_stages.size():
		return null
	return shape_stages[current_stage]

## 规则改变：把扩展核叠到当前每一格上，只收下通过检测的新格子。
func _build_rule_expanded_shape(
	view: InventoryOperationView,
	source_item_instance_data: ItemInstanceData,
	source_identity: ItemInstanceData
) -> Shape:
	if rule_shape == null:
		return null
	var rule_offsets: Array[Vector2i] = rule_shape.get_cells()
	if rule_offsets.is_empty():
		return null
	var current_local_cells: Array[Vector2i] = source_item_instance_data.get_local_cells().duplicate()
	if current_local_cells.is_empty():
		current_local_cells = [Vector2i.ZERO]
	var center_cell := view.get_cell(source_identity)
	var next_local_cells: Array[Vector2i] = current_local_cells.duplicate()
	for current_cell in current_local_cells:
		for rule_offset in rule_offsets:
			var candidate_cell := current_cell + rule_offset
			if next_local_cells.has(candidate_cell):
				continue
			if !_can_expand_into_local_cell(
				view,
				source_identity,
				source_item_instance_data,
				candidate_cell,
				center_cell
			):
				continue
			next_local_cells.append(candidate_cell)
	if _are_local_cell_sets_equal(next_local_cells, current_local_cells):
		return null
	var expanded_shape := Shape.new()
	expanded_shape.cells = next_local_cells
	return expanded_shape

## 检测局部候选格对应的世界格是否在区域内且空闲（自身占用视为通过）。
func _can_expand_into_local_cell(
	view: InventoryOperationView,
	source_identity: ItemInstanceData,
	source_item_instance_data: ItemInstanceData,
	local_cell: Vector2i,
	center_cell: Vector2i
) -> bool:
	var world_cells := source_item_instance_data.get_cells_for_local_cells(
		[local_cell],
		source_item_instance_data.dir,
		center_cell
	)
	if world_cells.is_empty():
		return false
	for cell in world_cells:
		if not view.get_region().has(cell):
			return false
		var occupant := view.get_item_at(cell)
		if occupant != null and occupant != source_identity:
			return false
	return true

## 判断两组局部格子是否表示同一集合。
func _are_local_cell_sets_equal(cells_a: Array[Vector2i], cells_b: Array[Vector2i]) -> bool:
	if cells_a.size() != cells_b.size():
		return false
	for cell in cells_b:
		if !cells_a.has(cell):
			return false
	return true
