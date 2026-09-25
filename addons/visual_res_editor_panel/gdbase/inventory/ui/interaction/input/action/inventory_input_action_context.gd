class_name InventoryInputActionContext
extends RefCounted
## 一次库存语义动作的只读约定快照；不得被 Processor 保存。
##
## 控制器分发时构造：action_id 取自 InventoryInputActionIds 词典，
## target_* 为当前指向目标，held_item 从 held_item_session 派生（无手持为 null）。

var action_id: StringName
var controller: InventoryItemsInputController
var inventory: InventoryData
var target_item: ItemInstanceData
var target_cell: Vector2i = Vector2i(-1, -1)
var held_item: ItemInstanceData
var held_item_session: InventoryHeldItemSession
var transfer_center: InventoryHostTransferCenter


static func create(
	action_id_: StringName,
	controller_: InventoryItemsInputController,
	inventory_: InventoryData,
	target_item_: ItemInstanceData,
	target_cell_: Vector2i,
	held_item_session_: InventoryHeldItemSession,
	transfer_center_: InventoryHostTransferCenter
) -> InventoryInputActionContext:
	var context := InventoryInputActionContext.new()
	context.action_id = action_id_
	context.controller = controller_
	context.inventory = inventory_
	context.target_item = target_item_
	context.target_cell = target_cell_
	context.held_item_session = held_item_session_
	context.transfer_center = transfer_center_
	if is_instance_valid(held_item_session_):
		context.held_item = held_item_session_.get_held_item()
	return context
