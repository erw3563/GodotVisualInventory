@tool
class_name InventoryTargetCounterFilter
extends InventoryTargetFilter
## 按稳定键选择具备指定计数器能力的物品。

@export var counter_key: String = ""

func validate_configuration() -> StringName:
	return &"invalid_counter_key" if counter_key.is_empty() else &""

func matches(item: ItemInstanceData, context: InventoryTargetQueryContext) -> bool:
	var fact := context.get_item(item)
	return fact != null and ItemCounterPart.find(fact.item_data, counter_key) != null
