class_name InventoryOperationEffect
extends RefCounted
## 候选操作中的一项精确影响。

enum Type {
	LEAVE_INVENTORY,
	DESTROY_ITEM, # 移除库存成员且不产生可继续持有的操作产物。
	ENTER_INVENTORY,
	CHANGE_QUANTITY,
	CHANGE_POSITION,
	CHANGE_ROTATION,
	CHANGE_SHAPE,
	DISPLACE_ITEM,
	CONSUME_QUANTITY,
	CHANGE_STATES,
}

var type: Type
var item: ItemInstanceData
var inventory: InventoryData
var quantity_before: int = -1
var quantity_after: int = -1
var cell_before: Vector2i = Vector2i(-1, -1)
var cell_after: Vector2i = Vector2i(-1, -1)
var dir_before: Vector2 = Vector2.ZERO
var dir_after: Vector2 = Vector2.ZERO
var shape_before: Shape
var shape_after: Shape
## LEAVE 是否真的移除成员；部分拿取只离开数量，不移除原堆。
var removes_membership: bool = true


static func create(effect_type: Type, affected_item: ItemInstanceData, affected_inventory: InventoryData = null) -> InventoryOperationEffect:
	var effect := InventoryOperationEffect.new()
	effect.type = effect_type
	effect.item = affected_item
	effect.inventory = affected_inventory
	return effect
