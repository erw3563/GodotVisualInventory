class_name InventoryInputActionObserver
extends Resource
## 动作前后观察协议；不参与认领，也不得改写动作结果。
##
## 观察所有动作的分发边界：before_action 返回的 token 原样传给 after_action
## （棋局撤回以此对做背包指纹快照）；处理器链是否中途终止不影响成对执行。


func before_action(_context: InventoryInputActionContext) -> Variant:
	return null


func after_action(
	_context: InventoryInputActionContext,
	_result: InventoryInputActionResult,
	_token: Variant
) -> void:
	pass
