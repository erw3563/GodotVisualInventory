class_name InventoryInputActionRoute
extends Resource
## 一个动作 ID 对应的有序 Processor 链。
##
## 链序由 InventoryInputConfigurationComposer 按功能 input_priority 降序合并
## （同优先级保持 features 声明序）：高优先级功能（如商店 p100）的处理器
## 永远排在标准处理器之前，链上先表态者终局。

@export var action_id: StringName
@export var processors: Array[InventoryInputActionProcessor] = []


static func create(
	action_id_: StringName,
	processors_: Array[InventoryInputActionProcessor]
) -> InventoryInputActionRoute:
	var route := InventoryInputActionRoute.new()
	route.action_id = action_id_
	route.processors = processors_
	return route
