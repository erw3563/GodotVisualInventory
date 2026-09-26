class_name InventoryTransferOperations
extends RefCounted
## 无界面库存转移操作：通过 Request／Plan／Commit 管线规划和提交单件及批量转移。
## 调用方提供显式操作上下文和源、目标库存，返回规划裁决或实际提交结果。

## 规划单个跨库存转移；不修改任一库存。
static func plan_transfer_item(
	operation_context: InventoryOperationContext, source_inventory: InventoryData,
	target_inventory: InventoryData,
	item_instance: ItemInstanceData,
	requested_quantity: int = -1
) -> InventoryOperationDecision:
	var request := InventoryOperationRequest.create(operation_context,
		InventoryOperationRequest.Type.TRANSFER, item_instance
	)
	request.source_inventory = source_inventory
	request.target_inventory = target_inventory
	request.requested_quantity = requested_quantity
	return InventoryOperationPlanner.plan(request)


## 将单个物品从源背包转移到目标背包，来源离开与目标进入共用一份 Plan。
static func try_transfer_item(
	operation_context: InventoryOperationContext, source_inventory: InventoryData,
	target_inventory: InventoryData,
	item_instance: ItemInstanceData,
	requested_quantity: int = -1
) -> InventoryOperationResult:
	var decision := plan_transfer_item(operation_context, source_inventory, target_inventory, item_instance, requested_quantity)
	if !decision.allowed:
		return InventoryOperationResult.failed(decision.reason_key)
	return InventoryOperationCommitter.commit(decision.plan)


## 尽可能将源背包全部物品转移到目标背包，返回成功转移的物品实例数；
## 装不下的留在源背包，不是整批原子事务。
static func try_transfer_all(
	operation_context: InventoryOperationContext, source_inventory: InventoryData,
	target_inventory: InventoryData
) -> int:
	if source_inventory == null or target_inventory == null:
		return 0
	if source_inventory == target_inventory:
		return 0
	var transferred_count := 0
	var source_items := source_inventory.get_item_instances().duplicate()
	for source_item_instance in source_items:
		if try_transfer_item(operation_context, source_inventory, target_inventory, source_item_instance).success:
			transferred_count += 1
	return transferred_count
