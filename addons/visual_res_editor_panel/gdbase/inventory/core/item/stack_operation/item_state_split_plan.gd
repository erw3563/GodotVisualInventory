class_name ItemStateSplitPlan
extends RefCounted
## 一个稳定 State 键的纯拆分结果。

var allowed: bool = false
var reason_key: StringName
var remaining_state: ItemInstanceState
var split_state: ItemInstanceState


static func accept(
	result_remaining_state: ItemInstanceState,
	result_split_state: ItemInstanceState
) -> ItemStateSplitPlan:
	var plan := ItemStateSplitPlan.new()
	plan.allowed = true
	plan.remaining_state = result_remaining_state
	plan.split_state = result_split_state
	return plan


static func reject(reason: StringName) -> ItemStateSplitPlan:
	var plan := ItemStateSplitPlan.new()
	plan.reason_key = reason
	return plan
