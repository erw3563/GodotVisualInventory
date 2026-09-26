@tool
class_name ItemShapePart
extends ItemPart
## 物品格子轮廓拼图。无此拼图时物品默认为一格。

## 模板轮廓。
@export var shape: Shape = Shape.new()
enum StackMergeMode {
	DISABLED,
	SAME_SHAPE_STATE,
}
## 本形状能力自己的堆叠规则；库存核心不解释此枚举。
@export var stack_merge_mode: StackMergeMode = StackMergeMode.DISABLED

static func get_part_type() -> String:
	return "Shape"

func allows_multiple() -> bool:
	return false

## 静态轮廓仍拥有堆叠门禁，不能因未创建 State 而绕过。
func plan_stack_merge(_context: ItemStackMergeContext) -> ItemStateMergePlan:
	match stack_merge_mode:
		StackMergeMode.DISABLED:
			return ItemStateMergePlan.reject(&"shape_stack_merge_disabled")
		StackMergeMode.SAME_SHAPE_STATE:
			return ItemStateMergePlan.accept(null, null)
	return ItemStateMergePlan.reject(&"unknown_shape_stack_merge_mode")

## 构建形状描述面板。
func get_description_panel() -> Array[Control]:
	return [ItemShapeDescriptionControl.create(ShapeTransform.cells_from_shape(shape))]
