class_name StandardRotateInputActionProcessor
extends InventoryInputActionProcessor
## 标准旋转动作。
##
## 动作：ROTATE。语义：旋转手持（经 HeldItemSession）或目标物品的朝向；
## 无手持且无目标时 PASS，执行失败 REJECTED（inventory_rotate_rejected）。


func process(context: InventoryInputActionContext) -> InventoryInputActionResult:
	if context == null or !is_instance_valid(context.controller):
		return InventoryInputActionResult.pass_result()
	if !context.controller.can_process_rotate_action(context):
		return InventoryInputActionResult.pass_result()
	if context.controller.perform_rotate_action(context):
		return InventoryInputActionResult.handled()
	return InventoryInputActionResult.rejected(&"inventory_rotate_rejected")
