class_name ShopRotateInputActionProcessor
extends ShopInputActionProcessor

func process(context: InventoryInputActionContext) -> InventoryInputActionResult:
	if context == null:
		return InventoryInputActionResult.rejected(&"shop_context_missing")
	if context.action_id != InventoryInputActionIds.ROTATE:
		return InventoryInputActionResult.pass_result()
	if not has_live_session(context):
		return InventoryInputActionResult.rejected(&"shop_session_missing")
	if not context.controller.can_process_rotate_action(context):
		return InventoryInputActionResult.rejected(&"shop_rotate_target_missing")
	return operation_result(context.held_item_session.try_rotate_held_item() if context.held_item != null else session.try_rotate_in_stock_best_effort(context.controller.get_operation_context(), context.target_item))
