class_name ItemStateMergePlan
extends RefCounted
## 一个稳定 State 键的纯合并结果；也可表达静态 Part 的许可或拒绝。

var allowed: bool = false
var reason_key: StringName
var target_state: ItemInstanceState
var source_state: ItemInstanceState


static func accept(
	result_target_state: ItemInstanceState = null,
	result_source_state: ItemInstanceState = null
) -> ItemStateMergePlan:
	var plan := ItemStateMergePlan.new()
	plan.allowed = true
	plan.target_state = result_target_state
	plan.source_state = result_source_state
	return plan


static func reject(reason: StringName) -> ItemStateMergePlan:
	var plan := ItemStateMergePlan.new()
	plan.reason_key = reason
	return plan
