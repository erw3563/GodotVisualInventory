@tool
class_name ItemReactionSelfOutput
extends ItemReactionOutputSource
## 运行时读取触发物品模板，资源无需引用自身。
@export_range(1, 100000, 1) var quantity := 1
func validate_configuration() -> StringName:
	return &"" if quantity > 0 else &"invalid_output_quantity"
func sample(context: ItemReactionPlanContext) -> Array[ItemReactionOutputEntry]:
	if context.source == null:
		return []
	var source := context.view.get_item(context.source)
	if source == null or source.item_data == null:
		return []
	var entry := ItemReactionOutputEntry.new()
	entry.item_data = source.item_data
	entry.quantity = quantity
	return [entry]
