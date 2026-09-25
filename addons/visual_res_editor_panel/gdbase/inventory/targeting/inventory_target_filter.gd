@abstract
class_name InventoryTargetFilter
extends Resource
## 按物品特征筛选候选原身份，通过 context.get_item 读取本次实例事实。

func validate_configuration() -> StringName:
	return &""

func validate_context(_context: InventoryTargetQueryContext) -> StringName:
	return &""

@abstract func matches(item: ItemInstanceData, context: InventoryTargetQueryContext) -> bool
