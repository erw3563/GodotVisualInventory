class_name StandardQuickTransferInputActionProcessor
extends InventoryInputActionProcessor
## 标准快捷转移动作。
##
## 动作：QUICK_TRANSFER / QUICK_TRANSFER_SINGLE。语义：不经手持，经转移中心把目标物品转到
## 配对的另一背包；前置不满足 PASS，失败 REJECTED
## （inventory_quick_transfer_rejected）并播放无效反馈。


func process(context: InventoryInputActionContext) -> InventoryInputActionResult:
	if context == null or !is_instance_valid(context.controller):
		return InventoryInputActionResult.pass_result()
	if !context.controller.can_process_quick_transfer_action(context):
		return InventoryInputActionResult.pass_result()
	if ItemSupplyProcessor.uses_infinite_supply(context):
		return InventoryInputActionResult.rejected(&"infinite_items_transfer_unsupported")
	if context.controller.perform_quick_transfer_action(context):
		return InventoryInputActionResult.handled()
	return InventoryInputActionResult.rejected(&"inventory_quick_transfer_rejected")
