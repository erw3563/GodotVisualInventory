class_name ShopPlaceInputActionProcessor
extends ShopInputActionProcessor
## 整组和单件共用处理器，仅数量策略不同。
func process(context: InventoryInputActionContext) -> InventoryInputActionResult:
	if context == null:
		return InventoryInputActionResult.rejected(&"shop_context_missing")
	if context.action_id not in [InventoryInputActionIds.PRIMARY, InventoryInputActionIds.PRIMARY_SINGLE]:
		return InventoryInputActionResult.pass_result()
	if context.held_item == null:
		return InventoryInputActionResult.pass_result()
	if not has_live_session(context):
		return InventoryInputActionResult.rejected(&"shop_session_missing")
	return operation_result(_place(context, context.action_id == InventoryInputActionIds.PRIMARY_SINGLE))

func _place(context: InventoryInputActionContext, single: bool) -> bool:
	var item := context.held_item
	var success := false
	if context.controller.uses_automatic_placement():
		success = session.try_add_quantity_into_stock_with_merge(context.controller.get_operation_context(), item, 1) if single else session.try_add_into_stock_with_merge(context.controller.get_operation_context(), item)
	elif context.target_cell != Vector2i(-1, -1):
		var cell := context.target_cell
		if single:
			success = session.try_place_quantity_into_stock(context.controller.get_operation_context(), item, cell, 1) if context.inventory.get_occupy_map().get_item_in_cell(cell) == null else session.try_merge_quantity_into_stock_cell(context.controller.get_operation_context(), item, cell, 1)
		elif context.inventory.can_place_item_in_cell(context.controller.get_operation_context(), item, cell):
			success = session.try_place_into_stock(context.controller.get_operation_context(), item, cell)
		elif context.inventory.can_merge_item_in_cell(context.controller.get_operation_context(), item, cell):
			success = session.try_merge_into_stock_cell(context.controller.get_operation_context(), item, cell)
		elif context.inventory.can_replace_item_in_cell(context.controller.get_operation_context(), item, cell):
			var replaced := session.try_replace_in_stock_cell(context.controller.get_operation_context(), item, cell)
			if replaced != null:
				context.held_item_session.clear_hold()
				context.controller.pick_item_instance(replaced, cell)
				return true
	if success and (item.num <= 0 or context.inventory.has_item_instance(item)):
		context.held_item_session.clear_hold()
	return success

