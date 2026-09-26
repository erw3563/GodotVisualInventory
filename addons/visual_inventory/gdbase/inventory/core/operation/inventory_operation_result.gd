class_name InventoryOperationResult
extends RefCounted
## 操作提交结果。

var success: bool = false
var reason_key: StringName
var actual_quantity: int = 0
var replaced_item: ItemInstanceData
var output_item: ItemInstanceData
var plan: InventoryOperationPlan
enum Status { COMMITTED, STALE, REJECTED, COMMIT_FAILED }
var failure_path: Array[int] = []
var status: Status:
	get:
		if success:
			return Status.COMMITTED
		if reason_key in [&"stale_operation_plan", &"stale_operation_policy"]:
			return Status.STALE
		if reason_key == &"operation_commit_failed":
			return Status.COMMIT_FAILED
		return Status.REJECTED


static func succeeded(committed_plan: InventoryOperationPlan) -> InventoryOperationResult:
	var result := InventoryOperationResult.new()
	result.success = true
	result.plan = committed_plan
	result.actual_quantity = committed_plan.actual_quantity
	result.replaced_item = committed_plan.replaced_item
	result.output_item = committed_plan.output_item
	return result


static func failed(reason: StringName, candidate_plan: InventoryOperationPlan = null) -> InventoryOperationResult:
	var result := InventoryOperationResult.new()
	result.reason_key = reason
	result.plan = candidate_plan
	return result
