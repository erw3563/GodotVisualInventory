class_name InventoryTargetAllRule
extends InventoryTargetRule
## 按库存成员顺序提供全库存范围内的物品候选。

func _query_candidates(context: InventoryTargetQueryContext) -> InventoryTargetQueryResult:
	var result := InventoryTargetQueryResult.new()
	result.items = context.get_items()
	return result
