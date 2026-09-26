class_name ItemStackOperationPlanner
extends RefCounted
## Item 级合并 / 拆分纯规划器。库存核心只编排 Part、State 与确定结果。


static func plan_merge(
	target: ItemInstanceData,
	source: ItemInstanceData,
	requested_transfer_num: int = -1
) -> ItemStackOperationPlan:
	if target == null or source == null or target == source:
		return ItemStackOperationPlan.reject(&"invalid_stack_items")
	if target.item_data == null or target.item_data != source.item_data:
		return ItemStackOperationPlan.reject(&"different_item_template")
	if target.num <= 0 or source.num <= 0:
		return ItemStackOperationPlan.reject(&"invalid_stack_quantity")
	var capacity := target.get_remain_space_num()
	if capacity <= 0:
		return ItemStackOperationPlan.reject(&"stack_capacity_full")
	var transfer_num := mini(source.num, capacity)
	if requested_transfer_num >= 0:
		if requested_transfer_num <= 0 or requested_transfer_num > transfer_num:
			return ItemStackOperationPlan.reject(&"invalid_stack_quantity")
		transfer_num = requested_transfer_num

	var state_index_result := _build_state_pair_index(target, source)
	if !state_index_result.allowed:
		return state_index_result

	var plan := ItemStackOperationPlan.new()
	plan.type = ItemStackOperationPlan.Type.MERGE
	plan.target_item = target
	plan.source_item = source
	plan.target_num_before = target.num
	plan.source_num_before = source.num
	plan.target_num_after = target.num + transfer_num
	plan.source_num_after = source.num - transfer_num
	plan.transfer_num = transfer_num
	var target_by_key: Dictionary = state_index_result.get_meta("target_by_key")
	var source_by_key: Dictionary = state_index_result.get_meta("source_by_key")
	var schema: Dictionary = state_index_result.get_meta("part_by_key")

	for item_part in target.item_data.parts:
		if item_part == null:
			continue
		var prototype := item_part.create_instance_state()
		var state_key := ""
		var target_state: ItemInstanceState
		var source_state: ItemInstanceState
		if prototype != null:
			state_key = prototype.state_key
			target_state = target_by_key.get(state_key)
			source_state = source_by_key.get(state_key)
		var context := ItemStackMergeContext.create(
			target, source, item_part, item_part,
			target_state, source_state, transfer_num
		)
		var part_plan: ItemStateMergePlan = item_part.plan_stack_merge(context)
		if part_plan == null or !part_plan.allowed:
			return ItemStackOperationPlan.reject(
				part_plan.reason_key if part_plan != null and part_plan.reason_key != &"" \
				else &"stack_part_rejected"
			)
	# 按已有状态独立规划，支持没有 Part 的合法内建状态。
	for state_key: String in target_by_key:
		var target_state := target_by_key[state_key] as ItemInstanceState
		var source_state := source_by_key[state_key] as ItemInstanceState
		var item_part := schema[state_key].part as ItemPart
		var context := ItemStackMergeContext.create(
			target, source, item_part, item_part, target_state, source_state, transfer_num
		)
		var state_plan: ItemStateMergePlan = target_state.plan_stack_merge(context)
		if state_plan == null or !state_plan.allowed:
			return ItemStackOperationPlan.reject(
				state_plan.reason_key if state_plan != null and state_plan.reason_key != &"" \
				else &"stack_state_rejected"
			)
		if !_is_valid_merge_result(state_key, state_plan, target_state, source_state, plan.source_num_after):
			return ItemStackOperationPlan.reject(&"invalid_stack_state_result")
		plan.target_states.append(state_plan.target_state)
		if plan.source_num_after > 0:
			plan.source_states.append(state_plan.source_state)
	plan.allowed = true
	plan.capture_facts()
	return plan


static func plan_split(item: ItemInstanceData, split_num: int) -> ItemStackOperationPlan:
	if item == null or item.item_data == null:
		return ItemStackOperationPlan.reject(&"invalid_stack_items")
	if split_num <= 0 or split_num >= item.num:
		return ItemStackOperationPlan.reject(&"invalid_stack_quantity")
	var state_index_result := _build_single_state_index(item)
	if !state_index_result.allowed:
		return state_index_result
	var state_by_key: Dictionary = state_index_result.get_meta("state_by_key")
	var plan := ItemStackOperationPlan.new()
	plan.type = ItemStackOperationPlan.Type.SPLIT
	plan.target_item = item
	plan.target_num_before = item.num
	plan.target_num_after = item.num - split_num
	plan.source_num_after = split_num
	plan.transfer_num = split_num
	var schema: Dictionary = state_index_result.get_meta("part_by_key")
	for state_key: String in state_by_key:
		var item_part := schema[state_key].part as ItemPart
		var state := state_by_key.get(state_key) as ItemInstanceState
		var context := ItemStackSplitContext.create(item, item_part, state, split_num)
		var state_plan: ItemStateSplitPlan = state.plan_stack_split(context)
		if state_plan == null or !state_plan.allowed:
			return ItemStackOperationPlan.reject(
				state_plan.reason_key if state_plan != null and state_plan.reason_key != &"" \
				else &"stack_state_split_rejected"
			)
		if !_is_valid_split_result(state_key, state_plan, state):
			return ItemStackOperationPlan.reject(&"invalid_stack_state_result")
		plan.target_states.append(state_plan.remaining_state)
		plan.source_states.append(state_plan.split_state)
	plan.allowed = true
	plan.capture_facts()
	return plan


static func _build_state_pair_index(
	target: ItemInstanceData,
	source: ItemInstanceData
) -> ItemStackOperationPlan:
	var target_result := _build_state_index(target)
	if !target_result.allowed:
		return target_result
	var source_result := _build_state_index(source)
	if !source_result.allowed:
		return source_result
	var target_by_key: Dictionary = target_result.get_meta("state_by_key")
	var source_by_key: Dictionary = source_result.get_meta("state_by_key")
	var part_by_key: Dictionary = target_result.get_meta("part_by_key")
	if target_by_key.size() != source_by_key.size():
		return ItemStackOperationPlan.reject(&"stack_state_missing")
	for state_key in target_by_key:
		if !source_by_key.has(state_key):
			return ItemStackOperationPlan.reject(&"stack_state_missing")
		var expected_script: Script = part_by_key[state_key].state_script
		if (target_by_key[state_key] as ItemInstanceState).get_script() != expected_script \
				or (source_by_key[state_key] as ItemInstanceState).get_script() != expected_script:
			return ItemStackOperationPlan.reject(&"stack_state_type_mismatch")
	var result := ItemStackOperationPlan.new()
	result.allowed = true
	result.set_meta("target_by_key", target_by_key)
	result.set_meta("source_by_key", source_by_key)
	result.set_meta("part_by_key", part_by_key)
	return result


static func _build_single_state_index(item: ItemInstanceData) -> ItemStackOperationPlan:
	var result := _build_state_index(item)
	if !result.allowed:
		return result
	var state_by_key: Dictionary = result.get_meta("state_by_key")
	var part_by_key: Dictionary = result.get_meta("part_by_key")
	for state_key in part_by_key:
		if !state_by_key.has(state_key):
			if part_by_key[state_key].required:
				return ItemStackOperationPlan.reject(&"stack_state_missing")
			continue
		if (state_by_key[state_key] as ItemInstanceState).get_script() != part_by_key[state_key].state_script:
			return ItemStackOperationPlan.reject(&"stack_state_type_mismatch")
	return result


static func _build_state_index(item: ItemInstanceData) -> ItemStackOperationPlan:
	var state_by_key: Dictionary = {}
	for state in item.instance_states:
		if state == null or state.state_key.is_empty():
			return ItemStackOperationPlan.reject(&"invalid_stack_state_key")
		if state_by_key.has(state.state_key):
			return ItemStackOperationPlan.reject(&"duplicate_stack_state_key")
		state_by_key[state.state_key] = state
	var part_by_key: Dictionary = {}
	if !ItemInstanceStateBuilder.try_build_part_state_index(item.item_data, part_by_key):
		return ItemStackOperationPlan.reject(&"invalid_part_state_schema")
	for state_key in part_by_key:
		if part_by_key[state_key].required and not state_by_key.has(state_key):
			return ItemStackOperationPlan.reject(&"stack_state_missing")
	for state_key in state_by_key:
		if !part_by_key.has(state_key):
			return ItemStackOperationPlan.reject(&"stack_state_part_missing")
		var state := state_by_key[state_key] as ItemInstanceState
		if state.get_script() != part_by_key[state_key].state_script or not state.is_valid_instance_state():
			return ItemStackOperationPlan.reject(&"stack_state_type_mismatch")
	var result := ItemStackOperationPlan.new()
	result.allowed = true
	result.set_meta("state_by_key", state_by_key)
	result.set_meta("part_by_key", part_by_key)
	return result


static func _is_valid_merge_result(
	state_key: String,
	state_plan: ItemStateMergePlan,
	target_state: ItemInstanceState,
	source_state: ItemInstanceState,
	source_num_after: int
) -> bool:
	if state_plan.target_state == null or state_plan.target_state.state_key != state_key:
		return false
	if state_plan.target_state == target_state or state_plan.target_state == source_state:
		return false
	if source_num_after <= 0:
		return state_plan.source_state == null
	if state_plan.source_state == null or state_plan.source_state.state_key != state_key:
		return false
	if state_plan.source_state == target_state or state_plan.source_state == source_state:
		return false
	return state_plan.source_state != state_plan.target_state


static func _is_valid_split_result(
	state_key: String,
	state_plan: ItemStateSplitPlan,
	original_state: ItemInstanceState
) -> bool:
	if state_plan.remaining_state == null or state_plan.split_state == null:
		return false
	if state_plan.remaining_state.state_key != state_key or state_plan.split_state.state_key != state_key:
		return false
	if state_plan.remaining_state == original_state or state_plan.split_state == original_state:
		return false
	return state_plan.remaining_state != state_plan.split_state
