class_name InventoryReactionScheduleResult
extends RefCounted
## 调度结果不是库存提交结果。
var queued := false
var reason_key: StringName

static func create(accepted: bool, reason: StringName = &"") -> InventoryReactionScheduleResult:
	var result := InventoryReactionScheduleResult.new()
	result.queued = accepted
	result.reason_key = reason
	return result
