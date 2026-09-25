class_name ShopTakeInputActionProcessor
extends ShopInputActionProcessor
## 整组和单件共用处理器，仅数量策略不同。
func process(context: InventoryInputActionContext) -> InventoryInputActionResult:
	if context == null:
		return InventoryInputActionResult.rejected(&"shop_context_missing")
	if context.action_id not in [InventoryInputActionIds.PRIMARY, InventoryInputActionIds.PRIMARY_SINGLE]:
		return InventoryInputActionResult.pass_result()
	if context.held_item != null:
		return InventoryInputActionResult.pass_result()
	if not has_live_session(context):
		return InventoryInputActionResult.rejected(&"shop_session_missing")
	return operation_result(_take(context, context.action_id == InventoryInputActionIds.PRIMARY_SINGLE))

func _take(context: InventoryInputActionContext, single: bool) -> bool:
	var item := context.target_item
	if item == null:
		return false
	var source_cell := context.inventory.get_occupy_map().get_item_center_cell(item)
	if single:
		var taken := session.try_take_quantity_from_stock(context.controller.get_operation_context(), item, 1)
		if taken == null:
			return false
		context.controller.pick_item_instance(taken)
		return true
	if not session.try_take_from_stock(context.controller.get_operation_context(), item):
		return false
	context.controller.pick_item_instance(item, source_cell)
	return true

