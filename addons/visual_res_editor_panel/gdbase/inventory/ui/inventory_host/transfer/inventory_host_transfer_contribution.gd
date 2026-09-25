class_name InventoryHostTransferContribution
extends RefCounted
## 一次转移的本端审查结果和结算凭据。
var reason: StringName = &""
var settlements: Array[InventoryOperationSettlementParticipant] = []
var validity_check: Callable

func validate() -> StringName:
	if reason != &"":
		return reason
	return validity_check.call() if validity_check.is_valid() else &""

static func rejected(cause: StringName) -> InventoryHostTransferContribution:
	var result := InventoryHostTransferContribution.new()
	result.reason = cause
	return result
