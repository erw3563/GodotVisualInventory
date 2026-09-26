class_name InventoryOperationRequest
extends RefCounted
## 库存操作意图；只描述调用方想做什么，不修改任何运行时事实。

enum Type {
	TAKE,
	DESTROY, # 永久结束来源库存对完整物品实例的所有权。
	PLACE_AT,
	ADD_WITH_MERGE,
	ADD_WITHOUT_MERGE,
	MERGE_AT,
	REPLACE_AT,
	MOVE_WITHIN,
	ROTATE,
	RESHAPE,
	TRANSFER,
	RELAYOUT,
	CONSUME, # 精确数量永久消耗，无可继续持有的产物。
	UPDATE_STATES, # 同库存实例的隔离 State 结果，不改变占格。
}

var operation_context: InventoryOperationContext
var type: Type
var source_inventory: InventoryData
var target_inventory: InventoryData
var item: ItemInstanceData
## -1 表示该操作的整件/整堆语义；正整数表示精确数量。各操作类型决定是否接受部分数量。
var requested_quantity: int = -1
var target_cell: Vector2i = Vector2i(-1, -1)
var rotate_step: int = 0
## RESHAPE 的唯一轮廓来源：变形处理器准备的隔离状态结果。
var shape_result: ItemInstanceState
var caller: StringName
var state_results: Array[ItemInstanceState] = []


static func create(context: InventoryOperationContext, operation_type: Type, operation_item: ItemInstanceData) -> InventoryOperationRequest:
	var request := InventoryOperationRequest.new()
	request.operation_context = context
	request.type = operation_type
	request.item = operation_item
	return request
