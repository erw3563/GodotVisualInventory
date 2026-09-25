class_name NestedInventoryQuery
extends RefCounted
## 嵌套库存专属查询：从物品实例收集 ItemInventoryPart 声明的子库存。


## 聚合本件全部嵌套 Part 的子库存；非法 State 或空引用关闭失败。
static func query_owned_inventories(item: ItemInstanceData) -> NestedInventoryQueryResult:
	if item == null or item.item_data == null:
		return NestedInventoryQueryResult.success()
	var owned: Array[InventoryData] = []
	for part in item.item_data.get_all_parts():
		if part == null or not (part is ItemInventoryPart):
			continue
		var query := (part as ItemInventoryPart).query_owned_inventories(item)
		if query == null or not query.valid:
			return NestedInventoryQueryResult.failure()
		for inventory in query.inventories:
			if inventory == null:
				return NestedInventoryQueryResult.failure()
			if not owned.has(inventory):
				owned.append(inventory)
	return NestedInventoryQueryResult.success(owned)


## 按 Part 实例状态键查询；非嵌套 Part 返回合法空结果。
static func query_from_part(part: ItemPart, item: ItemInstanceData) -> NestedInventoryQueryResult:
	if part == null:
		return NestedInventoryQueryResult.failure()
	if part is ItemInventoryPart:
		return (part as ItemInventoryPart).query_owned_inventories(item)
	return NestedInventoryQueryResult.success()
