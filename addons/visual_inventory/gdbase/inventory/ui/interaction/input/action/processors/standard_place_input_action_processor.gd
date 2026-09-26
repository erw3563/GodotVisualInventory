class_name StandardPlaceInputActionProcessor
extends InventoryInputActionProcessor
## 基础放置；整组与单件共用实例，数量由动作 ID 决定。

func process(context: InventoryInputActionContext) -> InventoryInputActionResult:
	if context == null or not is_instance_valid(context.controller):
		return InventoryInputActionResult.pass_result()
	if context.action_id not in [InventoryInputActionIds.PRIMARY, InventoryInputActionIds.PRIMARY_SINGLE] or context.held_item == null:
		return InventoryInputActionResult.pass_result()
	if not context.controller.can_process_primary_action(context):
		return InventoryInputActionResult.pass_result()
	if context.controller.try_lay_held_at_target(context, context.action_id == InventoryInputActionIds.PRIMARY_SINGLE):
		return InventoryInputActionResult.handled()
	return InventoryInputActionResult.rejected(&"inventory_place_rejected")
