@tool
class_name ItemShapeState
extends ItemInstanceState
## 本件运行时轮廓与变形阶段。

const SHAPE_STATE_KEY := "Shape"

## 已提交的独占运行时轮廓；存在 State 就必须有有效轮廓。
@export var runtime_shape: Shape
## 当前轮廓阶段，供变形规则选取下一份轮廓。
@export var shape_stage: int = 0

func _init() -> void:
	state_key = SHAPE_STATE_KEY

func is_valid_instance_state() -> bool:
	return state_key == SHAPE_STATE_KEY and shape_stage >= 0 \
		and runtime_shape != null and not runtime_shape.get_cells().is_empty()

## 只返回已提交轮廓；非法 State 不冒充模板形状。
func get_local_cells() -> Array[Vector2i]:
	if not is_valid_instance_state():
		push_error("ItemShapeState: 变形状态缺少有效轮廓或阶段非法")
		return []
	return runtime_shape.get_cells()

func plan_stack_merge(context: ItemStackMergeContext) -> ItemStateMergePlan:
	var other_shape := context.source_state as ItemShapeState
	if other_shape == null or not is_valid_instance_state() or not other_shape.is_valid_instance_state():
		return ItemStateMergePlan.reject(&"shape_stack_state_mismatch")
	if shape_stage != other_shape.shape_stage \
		or not ShapeTransform.are_cell_sets_equal(get_local_cells(), other_shape.get_local_cells()):
		return ItemStateMergePlan.reject(&"shape_stack_state_different")
	return ItemStateMergePlan.accept(
		duplicate_state(),
		other_shape.duplicate_state() if context.source_num > context.transfer_num else null
	)

## 形状状态类型。
func get_state_type() -> String:
	return SHAPE_STATE_KEY

## 按当前局部格子构建形状描述。
func get_description_panel_for_cells(local_cells: Array[Vector2i], direction: Vector2 = Vector2.RIGHT) -> Array[Control]:
	return [ItemShapeDescriptionControl.create(local_cells, direction)]

## 无格子上下文时用运行时轮廓或默认一格。
func get_description_panel() -> Array[Control]:
	var local_cells: Array[Vector2i] = []
	if runtime_shape != null:
		local_cells = runtime_shape.get_cells()
	if local_cells.is_empty():
		local_cells = [Vector2i.ZERO]
	return get_description_panel_for_cells(local_cells)
