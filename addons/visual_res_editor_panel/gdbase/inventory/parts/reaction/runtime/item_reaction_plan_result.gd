class_name ItemReactionPlanResult
extends RefCounted
enum Status { PLANNED, NOT_APPLICABLE, INVALID_CONFIGURATION }
var status: Status = Status.PLANNED
var reason_key: StringName
var step_path: Array[int] = []
static func planned() -> ItemReactionPlanResult:
	return ItemReactionPlanResult.new()
static func failed(reason: StringName, invalid: bool = false) -> ItemReactionPlanResult:
	var result := ItemReactionPlanResult.new()
	result.status = Status.INVALID_CONFIGURATION if invalid else Status.NOT_APPLICABLE
	result.reason_key = reason
	return result
func is_planned() -> bool:
	return status == Status.PLANNED
