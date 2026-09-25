class_name NestedInventoryQueryResult
extends RefCounted
## 嵌套库存能力对物品所拥有子库存的查询结果。

var valid: bool = true
var inventories: Array[InventoryData] = []
var reason_key: StringName


static func success(owned_inventories: Array[InventoryData] = []) -> NestedInventoryQueryResult:
	var result := NestedInventoryQueryResult.new()
	result.inventories = owned_inventories.duplicate()
	return result


static func failure(reason: StringName = &"invalid_inventory_ownership") -> NestedInventoryQueryResult:
	var result := NestedInventoryQueryResult.new()
	result.valid = false
	result.reason_key = reason
	return result
