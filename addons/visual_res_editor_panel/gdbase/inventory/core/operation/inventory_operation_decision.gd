class_name InventoryOperationDecision
extends RefCounted
## 规划或规则裁决结果。

var allowed: bool = false
var plan: InventoryOperationPlan
var reason_key: StringName
var provider_type: int = -1
var provider: Variant
var diagnostic: String = ""


static func allow(candidate_plan: InventoryOperationPlan = null) -> InventoryOperationDecision:
	var decision := InventoryOperationDecision.new()
	decision.allowed = true
	decision.plan = candidate_plan
	return decision


static func reject(reason: StringName, details: String = "") -> InventoryOperationDecision:
	var decision := InventoryOperationDecision.new()
	decision.allowed = false
	decision.reason_key = reason
	decision.diagnostic = details
	return decision
