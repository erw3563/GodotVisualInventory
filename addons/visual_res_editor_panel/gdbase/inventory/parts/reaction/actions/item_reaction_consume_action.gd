@tool
class_name ItemReactionConsumeAction
extends ItemReactionAction
@export var selector: ItemReactionTargetSelector
@export_range(1, 100000, 1) var quantity := 1
func validate_configuration() -> StringName:
	if selector == null or quantity <= 0:
		return &"invalid_consume_configuration"
	return selector.validate_configuration()
func plan(context: ItemReactionPlanContext) -> ItemReactionPlanResult:
	var reason := validate_configuration()
	if reason != &"":
		return ItemReactionPlanResult.failed(reason, true)
	var queried := selector.query(context)
	if queried.error_code != &"":
		return ItemReactionPlanResult.failed(queried.error_code)
	var remaining := quantity
	var selected: Dictionary = {}
	for item in queried.items:
		var snapshot := context.view.get_item(item)
		# 通过嵌套库存查询核验材料持有的子库存。
		var owned := NestedInventoryQuery.query_owned_inventories(snapshot)
		if owned == null or not owned.valid:
			return ItemReactionPlanResult.failed(&"invalid_inventory_ownership")
		for inventory in owned.inventories:
			if inventory == null or not inventory.get_item_instances().is_empty():
				return ItemReactionPlanResult.failed(&"consume_owned_inventory_not_empty")
		var amount := mini(remaining, snapshot.num)
		selected[item] = amount
		remaining -= amount
		if remaining == 0:
			break
	if remaining > 0:
		return ItemReactionPlanResult.failed(&"insufficient_consume_quantity")
	for item in selected:
		var result := context.append(InventoryOperationRequest.Type.CONSUME, item, selected[item])
		if not result.is_planned():
			return result
	return ItemReactionPlanResult.planned()
