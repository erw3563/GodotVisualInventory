class_name NestedInventoryOpenProcessor
extends InventoryInputActionProcessor
## Host 局部动作适配器：只把 OPEN 语义转发给 Part Processor 节点。
##
## 动作：OPEN。Part Processor 解析目标物品的嵌套 Part/State 并经窗口服务
## 开子面板：目标无嵌套 Part 时 PASS；State 缺失、类型或面板定义不合法等
## 以稳定原因 REJECTED。

var part_processor: NestedInventoryPartProcessor


func process(context: InventoryInputActionContext) -> InventoryInputActionResult:
	if not is_instance_valid(part_processor):
		return InventoryInputActionResult.rejected(&"nested_inventory_part_processor_unavailable")
	return part_processor.process_action(context)
