class_name ItemDescriptionInputActionProcessor
extends InventoryInputActionProcessor
## 描述动作只调用装配时显式注入的呈现入口。
var describe_item: Callable

func process(context: InventoryInputActionContext) -> InventoryInputActionResult:
	if context == null or context.target_item == null:
		return InventoryInputActionResult.pass_result()
	if not describe_item.is_valid():
		return InventoryInputActionResult.rejected(&"inventory_description_binding_missing")
	if describe_item.call(context.target_item):
		return InventoryInputActionResult.handled()
	return InventoryInputActionResult.rejected(&"inventory_description_rejected")
