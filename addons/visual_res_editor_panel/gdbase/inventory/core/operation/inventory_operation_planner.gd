class_name InventoryOperationPlanner
extends RefCounted
## 将操作意图规划成精确影响，并按稳定来源顺序执行 Rule。

static var _core_rules: Array[InventoryOperationRule] = []


static func plan(request: InventoryOperationRequest) -> InventoryOperationDecision:
	var validation := _validate_request(request)
	if !validation.allowed:
		return validation
	var candidate := InventoryOperationPlan.new()
	candidate.request = request
	candidate.policy_signature = request.operation_context.fingerprint()
	candidate.view = InventoryOperationView.new()
	candidate.view._inventory = request.source_inventory if request.source_inventory != null else request.target_inventory
	var build_decision := _build_plan(candidate)
	if !build_decision.allowed:
		return build_decision
	if request.type == InventoryOperationRequest.Type.RESHAPE:
		# 独立 Plan 与组合事务提供相同的预计 State / 占位视图。
		var projection := InventoryOperationTransaction.begin(request.operation_context, request.source_inventory)
		var projected := projection.append(request)
		if not projected.allowed:
			return projected
		candidate.after_view = projection.view
	var rule_decision := evaluate_rules(candidate)
	if !rule_decision.allowed:
		return rule_decision
	return InventoryOperationDecision.allow(candidate)


static func evaluate_rules(candidate: InventoryOperationPlan) -> InventoryOperationDecision:
	if candidate == null or candidate.request == null:
		return InventoryOperationDecision.reject(&"invalid_operation_plan")
	for rule in _core_rules:
		var context := _make_context(candidate, InventoryOperationRuleContext.ProviderType.CORE)
		var decision := _evaluate_rule(rule, context)
		if !decision.allowed:
			return decision
	var request := candidate.request
	if request.operation_context == null:
		return InventoryOperationDecision.reject(&"missing_operation_context")
	var reason := request.operation_context.validate(request.source_inventory, request.target_inventory)
	if reason != &"":
		return InventoryOperationDecision.reject(reason)
	var visited: Array[InventoryOperationEndpoint] = []
	for pair in [[request.source_inventory, request.operation_context.source_endpoint, InventoryOperationRuleContext.ProviderType.SOURCE_INVENTORY], [request.target_inventory, request.operation_context.target_endpoint, InventoryOperationRuleContext.ProviderType.TARGET_INVENTORY]]:
		var endpoint := pair[1] as InventoryOperationEndpoint
		if pair[0] == null or endpoint == null or endpoint in visited:
			continue
		visited.append(endpoint)
		var decision := _evaluate_endpoint(candidate, endpoint, pair[2])
		if not decision.allowed:
			return decision
	return InventoryOperationDecision.allow(candidate)


static func _validate_request(request: InventoryOperationRequest, validate_context: bool = true) -> InventoryOperationDecision:
	if request == null or request.item == null:
		return InventoryOperationDecision.reject(&"invalid_operation_request")
	if validate_context:
		if request.operation_context == null:
			return InventoryOperationDecision.reject(&"missing_operation_context")
		var context_reason := request.operation_context.validate(request.source_inventory, request.target_inventory)
		if context_reason != &"":
			return InventoryOperationDecision.reject(context_reason)
	if request.item.get_item_num() <= 0:
		return InventoryOperationDecision.reject(&"invalid_operation_quantity")
	if request.requested_quantity == 0 or request.requested_quantity < -1 \
			or request.requested_quantity > request.item.get_item_num():
		return InventoryOperationDecision.reject(&"invalid_operation_quantity")
	match request.type:
		InventoryOperationRequest.Type.CONSUME:
			if request.source_inventory == null or request.target_inventory != null or request.requested_quantity <= 0:
				return InventoryOperationDecision.reject(&"invalid_operation_quantity")
		InventoryOperationRequest.Type.UPDATE_STATES:
			if request.source_inventory == null or request.target_inventory != request.source_inventory:
				return InventoryOperationDecision.reject(&"invalid_operation_request")
		InventoryOperationRequest.Type.TAKE:
			if request.source_inventory == null or request.target_inventory != null:
				return InventoryOperationDecision.reject(&"invalid_operation_request")
			if !_is_valid_requested_quantity(request, true):
				return InventoryOperationDecision.reject(&"invalid_operation_quantity")
		InventoryOperationRequest.Type.DESTROY:
			if request.source_inventory == null or request.target_inventory != null \
					or request.requested_quantity != -1:
				return InventoryOperationDecision.reject(&"invalid_operation_request")
		InventoryOperationRequest.Type.PLACE_AT, \
		InventoryOperationRequest.Type.ADD_WITH_MERGE, \
		InventoryOperationRequest.Type.MERGE_AT:
			if request.target_inventory == null or request.source_inventory != null:
				return InventoryOperationDecision.reject(&"invalid_operation_request")
			if !_is_valid_requested_quantity(request, true):
				return InventoryOperationDecision.reject(&"invalid_operation_quantity")
		InventoryOperationRequest.Type.ADD_WITHOUT_MERGE, \
		InventoryOperationRequest.Type.REPLACE_AT:
			if request.target_inventory == null or request.source_inventory != null \
					or request.requested_quantity != -1:
				return InventoryOperationDecision.reject(&"invalid_operation_request")
		InventoryOperationRequest.Type.MOVE_WITHIN, \
		InventoryOperationRequest.Type.ROTATE, \
		InventoryOperationRequest.Type.RESHAPE, \
		InventoryOperationRequest.Type.RELAYOUT:
			if request.source_inventory == null or request.target_inventory != request.source_inventory \
					or request.requested_quantity != -1:
				return InventoryOperationDecision.reject(&"invalid_operation_request")
		InventoryOperationRequest.Type.TRANSFER:
			if request.source_inventory == null or request.target_inventory == null \
					or request.source_inventory == request.target_inventory:
				return InventoryOperationDecision.reject(&"invalid_operation_request")
		_:
			return InventoryOperationDecision.reject(&"unsupported_operation")
	return InventoryOperationDecision.allow()


static func _is_valid_requested_quantity(
	request: InventoryOperationRequest, allow_whole: bool
) -> bool:
	if allow_whole and request.requested_quantity == -1:
		return true
	return request.requested_quantity > 0 \
		and request.requested_quantity <= request.item.get_item_num()


static func _build_plan(candidate: InventoryOperationPlan) -> InventoryOperationDecision:
	var request := candidate.request
	match request.type:
		InventoryOperationRequest.Type.CONSUME:
			var consumed := _build_take(candidate)
			if not consumed.allowed:
				return consumed
			for effect in candidate.effects:
				if effect.type == InventoryOperationEffect.Type.LEAVE_INVENTORY:
					effect.type = InventoryOperationEffect.Type.CONSUME_QUANTITY
			if candidate.actual_quantity == request.item.num:
				var destroyed := InventoryOperationEffect.create(InventoryOperationEffect.Type.DESTROY_ITEM, request.item, request.source_inventory)
				destroyed.cell_before = request.source_inventory.occupy_map.get_item_center_cell(request.item)
				destroyed.quantity_before = request.item.num
				destroyed.quantity_after = 0
				candidate.effects.append(destroyed)
			return consumed
		InventoryOperationRequest.Type.UPDATE_STATES:
			return _build_state_update(candidate)
		InventoryOperationRequest.Type.TAKE:
			return _build_take(candidate)
		InventoryOperationRequest.Type.DESTROY:
			return _build_destroy(candidate)
		InventoryOperationRequest.Type.PLACE_AT:
			return _build_place(candidate)
		InventoryOperationRequest.Type.ADD_WITHOUT_MERGE:
			return _build_add_without_merge(candidate)
		InventoryOperationRequest.Type.ADD_WITH_MERGE:
			return _build_add_with_merge(candidate, false)
		InventoryOperationRequest.Type.MERGE_AT:
			return _build_merge(candidate)
		InventoryOperationRequest.Type.REPLACE_AT:
			return _build_replace(candidate)
		InventoryOperationRequest.Type.MOVE_WITHIN:
			return _build_move(candidate)
		InventoryOperationRequest.Type.ROTATE:
			return _build_rotate(candidate)
		InventoryOperationRequest.Type.RESHAPE:
			return _build_reshape(candidate)
		InventoryOperationRequest.Type.TRANSFER:
			return _build_add_with_merge(candidate, true)
		InventoryOperationRequest.Type.RELAYOUT:
			return _build_relayout(candidate)
	return InventoryOperationDecision.reject(&"unsupported_operation")


static func _build_take(candidate: InventoryOperationPlan) -> InventoryOperationDecision:
	var request := candidate.request
	if !request.source_inventory.has_item_instance(request.item):
		return InventoryOperationDecision.reject(&"source_item_missing")
	_capture(candidate, request.source_inventory, request.item)
	var take_quantity := request.requested_quantity
	if take_quantity == -1:
		take_quantity = request.item.get_item_num()
	if take_quantity < request.item.get_item_num():
		var split_plan := ItemStackOperationPlanner.plan_split(request.item, take_quantity)
		if !split_plan.allowed:
			return InventoryOperationDecision.reject(split_plan.reason_key)
		candidate.stack_plans.append(split_plan)
	var effect := InventoryOperationEffect.create(
		InventoryOperationEffect.Type.LEAVE_INVENTORY, request.item, request.source_inventory
	)
	effect.quantity_before = take_quantity
	effect.quantity_after = request.item.get_item_num() - take_quantity
	effect.cell_before = request.source_inventory.occupy_map.get_item_center_cell(request.item)
	effect.removes_membership = take_quantity == request.item.get_item_num()
	if !effect.removes_membership:
		_add_quantity_effect(
			candidate, request.item, request.source_inventory,
			request.item.get_item_num(), effect.quantity_after
		)
	candidate.actual_quantity = take_quantity
	candidate.add_effect(effect)
	return InventoryOperationDecision.allow(candidate)


## 为精确库存成员生成完整销毁影响。
static func _build_destroy(candidate: InventoryOperationPlan) -> InventoryOperationDecision:
	var request := candidate.request
	if !request.source_inventory.has_item_instance(request.item):
		return InventoryOperationDecision.reject(&"source_item_missing")
	_capture(candidate, request.source_inventory, request.item)
	var effect := InventoryOperationEffect.create(
		InventoryOperationEffect.Type.DESTROY_ITEM, request.item, request.source_inventory
	)
	effect.quantity_before = request.item.get_item_num()
	effect.quantity_after = 0
	effect.cell_before = request.source_inventory.occupy_map.get_item_center_cell(request.item)
	effect.dir_before = request.item.dir
	effect.removes_membership = true
	candidate.actual_quantity = effect.quantity_before
	candidate.add_effect(effect)
	return InventoryOperationDecision.allow(candidate)


static func _build_place(candidate: InventoryOperationPlan) -> InventoryOperationDecision:
	var request := candidate.request
	if request.target_inventory.has_item_instance(request.item):
		return InventoryOperationDecision.reject(&"item_already_in_target")
	var preparation := _prepare_requested_item(candidate)
	if !preparation.allowed:
		return preparation
	var operation_item := candidate.pending_item if candidate.pending_item != null else request.item
	if !InventoryOccupyMapQuery.can_place_item_in_cell(
		request.target_inventory.occupy_map, operation_item, request.target_cell
	):
		return InventoryOperationDecision.reject(&"target_position_unavailable")
	_capture(candidate, request.target_inventory, request.item)
	var effect := InventoryOperationEffect.create(
		InventoryOperationEffect.Type.ENTER_INVENTORY, operation_item, request.target_inventory
	)
	effect.cell_after = request.target_cell
	effect.dir_before = operation_item.dir
	effect.dir_after = operation_item.dir
	effect.quantity_after = operation_item.get_item_num()
	candidate.actual_quantity = operation_item.get_item_num()
	candidate.add_effect(effect)
	return InventoryOperationDecision.allow(candidate)


static func _build_add_without_merge(candidate: InventoryOperationPlan) -> InventoryOperationDecision:
	var request := candidate.request
	if request.target_inventory.has_item_instance(request.item):
		return InventoryOperationDecision.reject(&"item_already_in_target")
	var placement := request.target_inventory.occupy_map.get_free_placement_for_item(request.item, false)
	if placement.cell == Vector2i(-1, -1):
		return InventoryOperationDecision.reject(&"target_inventory_full")
	_capture(candidate, request.target_inventory, request.item)
	var effect := InventoryOperationEffect.create(
		InventoryOperationEffect.Type.ENTER_INVENTORY, request.item, request.target_inventory
	)
	effect.cell_after = placement.cell
	effect.dir_before = request.item.dir
	effect.dir_after = placement.dir
	effect.quantity_after = request.item.get_item_num()
	candidate.actual_quantity = request.item.get_item_num()
	candidate.add_effect(effect)
	return InventoryOperationDecision.allow(candidate)


static func _build_merge(candidate: InventoryOperationPlan) -> InventoryOperationDecision:
	var request := candidate.request
	var preparation := _prepare_requested_item(candidate)
	if !preparation.allowed:
		return preparation
	var operation_item := candidate.pending_item if candidate.pending_item != null else request.item
	var target_item := request.target_inventory.occupy_map.get_item_in_cell(request.target_cell)
	if target_item == null or target_item == request.item:
		return InventoryOperationDecision.reject(&"items_cannot_merge")
	var amount := mini(operation_item.get_item_num(), target_item.get_remain_space_num())
	if request.requested_quantity > 0 and amount != request.requested_quantity:
		return InventoryOperationDecision.reject(&"items_cannot_merge")
	if amount <= 0:
		return InventoryOperationDecision.reject(&"items_cannot_merge")
	var stack_plan := ItemStackOperationPlanner.plan_merge(target_item, operation_item, amount)
	if !stack_plan.allowed:
		return InventoryOperationDecision.reject(stack_plan.reason_key)
	candidate.stack_plans.append(stack_plan)
	_capture(candidate, request.target_inventory, request.item)
	candidate.capture_item(target_item, request.target_inventory)
	_add_quantity_effect(candidate, target_item, request.target_inventory, target_item.num, target_item.num + amount)
	_add_quantity_effect(candidate, operation_item, null, operation_item.num, operation_item.num - amount)
	if request.target_inventory.has_item_instance(operation_item) and operation_item.num == amount:
		var leave := InventoryOperationEffect.create(
			InventoryOperationEffect.Type.LEAVE_INVENTORY, operation_item, request.target_inventory
		)
		leave.cell_before = request.target_inventory.occupy_map.get_item_center_cell(operation_item)
		candidate.add_effect(leave)
	candidate.actual_quantity = amount
	return InventoryOperationDecision.allow(candidate)


static func _build_add_with_merge(
	candidate: InventoryOperationPlan, is_transfer: bool
) -> InventoryOperationDecision:
	var request := candidate.request
	var source := request.source_inventory if is_transfer else null
	var target := request.target_inventory
	if is_transfer and !source.has_item_instance(request.item):
		return InventoryOperationDecision.reject(&"source_item_missing")
	if target.has_item_instance(request.item):
		return InventoryOperationDecision.reject(&"item_already_in_target")
	if source != null:
		_capture(candidate, source, request.item)
		candidate.capture_inventory(target)
	else:
		_capture(candidate, target, request.item)
	var preparation := _prepare_requested_item(candidate)
	if !preparation.allowed:
		return preparation
	var operation_item := candidate.pending_item if candidate.pending_item != null else request.item
	var remaining := operation_item.get_item_num()
	var virtual_source := operation_item.duplicate_for_operation()
	for target_item in target.get_unfull_same_items(operation_item):
		if remaining <= 0:
			break
		var amount := mini(remaining, target_item.get_remain_space_num())
		var virtual_target := target_item.duplicate_for_operation()
		var virtual_plan := ItemStackOperationPlanner.plan_merge(
			virtual_target, virtual_source, amount
		)
		if !virtual_plan.allowed:
			continue
		var actual_plan := _retarget_stack_plan(
			virtual_plan, target_item, operation_item
		)
		candidate.stack_plans.append(actual_plan)
		ItemStackOperationCommitter.apply_prepared_merge(virtual_plan)
		candidate.capture_item(target_item, target)
		_add_quantity_effect(candidate, target_item, target, target_item.num, target_item.num + amount)
		remaining -= amount
	if remaining > 0:
		var placement := target.occupy_map.get_free_placement_for_item(operation_item, false)
		if placement.cell == Vector2i(-1, -1):
			return InventoryOperationDecision.reject(&"target_inventory_full")
		var enter := InventoryOperationEffect.create(
			InventoryOperationEffect.Type.ENTER_INVENTORY, operation_item, target
		)
		enter.cell_after = placement.cell
		enter.dir_before = operation_item.dir
		enter.dir_after = placement.dir
		enter.quantity_after = remaining
		candidate.add_effect(enter)
	if remaining != operation_item.num:
		_add_quantity_effect(candidate, operation_item, source if operation_item == request.item else null, operation_item.num, remaining)
	if is_transfer:
		var leave := InventoryOperationEffect.create(
			InventoryOperationEffect.Type.LEAVE_INVENTORY, request.item, source
		)
		leave.quantity_before = operation_item.num
		leave.quantity_after = request.item.num - operation_item.num
		leave.removes_membership = candidate.pending_item == null
		leave.cell_before = source.occupy_map.get_item_center_cell(request.item)
		candidate.add_effect(leave)
	candidate.actual_quantity = operation_item.get_item_num()
	return InventoryOperationDecision.allow(candidate)


## 为部分放入／转移生成未归属实例和同一 Plan 内的拆分影响，保留拆分拒绝原因。
static func _prepare_requested_item(candidate: InventoryOperationPlan) -> InventoryOperationDecision:
	var request := candidate.request
	var quantity := request.requested_quantity
	if quantity == -1 or quantity == request.item.get_item_num():
		return InventoryOperationDecision.allow(candidate)
	var split_plan := ItemStackOperationPlanner.plan_split(request.item, quantity)
	if !split_plan.allowed:
		return InventoryOperationDecision.reject(split_plan.reason_key)
	var pending := ItemInstanceData.new()
	pending.item_data = request.item.item_data
	pending.dir = request.item.dir
	pending.instance_states = split_plan.source_states
	pending.num = split_plan.source_num_after
	pending._mark_instance_states_ready()
	candidate.pending_item = pending
	candidate.stack_plans.append(split_plan)
	var source_inventory := request.source_inventory
	if source_inventory == null and request.target_inventory != null \
			and request.target_inventory.has_item_instance(request.item):
		source_inventory = request.target_inventory
	if source_inventory != null:
		candidate.capture_inventory(source_inventory)
	candidate.capture_item(request.item, source_inventory)
	candidate.capture_item(pending)
	_add_quantity_effect(
		candidate, request.item, source_inventory,
		request.item.get_item_num(), split_plan.target_num_after
	)
	return InventoryOperationDecision.allow(candidate)


static func _retarget_stack_plan(
	virtual_plan: ItemStackOperationPlan,
	target_item: ItemInstanceData,
	source_item: ItemInstanceData
) -> ItemStackOperationPlan:
	var retargeted_plan := ItemStackOperationPlan.new()
	retargeted_plan.allowed = virtual_plan.allowed
	retargeted_plan.reason_key = virtual_plan.reason_key
	retargeted_plan.type = virtual_plan.type
	retargeted_plan.target_item = target_item
	retargeted_plan.source_item = source_item
	retargeted_plan.target_num_before = virtual_plan.target_num_before
	retargeted_plan.source_num_before = virtual_plan.source_num_before
	retargeted_plan.target_num_after = virtual_plan.target_num_after
	retargeted_plan.source_num_after = virtual_plan.source_num_after
	retargeted_plan.transfer_num = virtual_plan.transfer_num
	retargeted_plan.target_states = virtual_plan.target_states
	retargeted_plan.source_states = virtual_plan.source_states
	return retargeted_plan


static func _build_replace(candidate: InventoryOperationPlan) -> InventoryOperationDecision:
	var request := candidate.request
	var replaced := InventoryOccupyMapQuery.get_replace_target_item(
		request.target_inventory.occupy_map, request.item, request.target_cell
	)
	if replaced == null:
		return InventoryOperationDecision.reject(&"replace_target_missing")
	_capture(candidate, request.target_inventory, request.item)
	candidate.capture_item(replaced, request.target_inventory)
	var leave := InventoryOperationEffect.create(
		InventoryOperationEffect.Type.LEAVE_INVENTORY, replaced, request.target_inventory
	)
	leave.quantity_before = replaced.num
	leave.quantity_after = 0
	leave.cell_before = request.target_inventory.occupy_map.get_item_center_cell(replaced)
	candidate.add_effect(leave)
	var displace := InventoryOperationEffect.create(
		InventoryOperationEffect.Type.DISPLACE_ITEM, replaced, request.target_inventory
	)
	displace.cell_before = leave.cell_before
	candidate.add_effect(displace)
	var enter := InventoryOperationEffect.create(
		InventoryOperationEffect.Type.ENTER_INVENTORY, request.item, request.target_inventory
	)
	enter.cell_after = request.target_cell
	enter.dir_before = request.item.dir
	enter.dir_after = request.item.dir
	enter.quantity_after = request.item.get_item_num()
	candidate.add_effect(enter)
	candidate.replaced_item = replaced
	candidate.actual_quantity = request.item.num
	return InventoryOperationDecision.allow(candidate)


static func _build_move(candidate: InventoryOperationPlan) -> InventoryOperationDecision:
	var request := candidate.request
	if !request.source_inventory.has_item_instance(request.item):
		return InventoryOperationDecision.reject(&"source_item_missing")
	if !InventoryOccupyMapQuery.can_place_item_in_cell(
		request.source_inventory.occupy_map, request.item, request.target_cell
	):
		return InventoryOperationDecision.reject(&"target_position_unavailable")
	_capture(candidate, request.source_inventory, request.item)
	var effect := InventoryOperationEffect.create(
		InventoryOperationEffect.Type.CHANGE_POSITION, request.item, request.source_inventory
	)
	effect.cell_before = request.source_inventory.occupy_map.get_item_center_cell(request.item)
	effect.cell_after = request.target_cell
	candidate.add_effect(effect)
	return InventoryOperationDecision.allow(candidate)


static func _build_rotate(candidate: InventoryOperationPlan) -> InventoryOperationDecision:
	var request := candidate.request
	if !request.source_inventory.has_item_instance(request.item):
		return InventoryOperationDecision.reject(&"source_item_missing")
	if !InventoryOccupyMapQuery.can_rotate_item_in_place(
		request.source_inventory.occupy_map, request.item, request.rotate_step
	):
		return InventoryOperationDecision.reject(&"rotation_unavailable")
	_capture(candidate, request.source_inventory, request.item)
	var effect := InventoryOperationEffect.create(
		InventoryOperationEffect.Type.CHANGE_ROTATION, request.item, request.source_inventory
	)
	effect.dir_before = request.item.dir
	effect.dir_after = ShapeTransform.rotate_dir_clockwise(request.item.dir, request.rotate_step)
	effect.cell_before = request.source_inventory.occupy_map.get_item_center_cell(request.item)
	candidate.add_effect(effect)
	return InventoryOperationDecision.allow(candidate)


static func _build_reshape(candidate: InventoryOperationPlan) -> InventoryOperationDecision:
	var request := candidate.request
	if !request.source_inventory.has_item_instance(request.item):
		return InventoryOperationDecision.reject(&"invalid_operation_request")
	if not ItemInstanceStateBuilder.validate_existing_states(request.item.instance_states, request.item.item_data):
		return InventoryOperationDecision.reject(&"invalid_reshape_state")
	if not request.item.is_valid_reshape_result(request.shape_result):
		return InventoryOperationDecision.reject(&"invalid_reshape_result")
	var prepared := request.shape_result.duplicate_for_operation()
	if prepared == null or prepared == request.shape_result or not request.item.is_valid_reshape_result(prepared):
		return InventoryOperationDecision.reject(&"invalid_reshape_result")
	for state in request.item.instance_states:
		if state.state_key != prepared.state_key:
			candidate.prepared_state_results.append(state)
	candidate.prepared_state_results.append(prepared)
	var projected := ItemInstanceData.new()
	projected.item_data = request.item.item_data
	projected.instance_states = candidate.prepared_state_results
	var new_shape := projected.get_shape_state().runtime_shape
	if ShapeTransform.are_cell_sets_equal(request.item.get_local_cells(), projected.get_local_cells()):
		return InventoryOperationDecision.reject(&"reshape_unchanged")
	if !InventoryOccupyMapQuery.can_reshape_item_in_place(
		request.source_inventory.occupy_map, request.item, new_shape
	):
		return InventoryOperationDecision.reject(&"reshape_unavailable")
	candidate.requested_states_signature = InventoryOperationFingerprint.of(request.shape_result)
	candidate.prepared_states_signature = InventoryOperationFingerprint.of(candidate.prepared_state_results)
	_capture(candidate, request.source_inventory, request.item)
	var effect := InventoryOperationEffect.create(
		InventoryOperationEffect.Type.CHANGE_SHAPE, request.item, request.source_inventory
	)
	effect.shape_after = new_shape
	effect.cell_before = request.source_inventory.occupy_map.get_item_center_cell(request.item)
	candidate.add_effect(effect)
	return InventoryOperationDecision.allow(candidate)


static func _build_relayout(candidate: InventoryOperationPlan) -> InventoryOperationDecision:
	var inventory := candidate.request.source_inventory
	var items := inventory.get_item_instances().duplicate()
	items.sort_custom(func(a: ItemInstanceData, b: ItemInstanceData) -> bool:
		return a.get_item_name().nocasecmp_to(b.get_item_name()) < 0
	)
	var layout_map := inventory.occupy_map.duplicate(true) as InventoryOccupyMap
	if layout_map == null:
		return InventoryOperationDecision.reject(&"relayout_unavailable")
	layout_map.clear_occupancy()
	candidate.capture_inventory(inventory)
	for item in items:
		candidate.capture_item(item, inventory)
		var placement := layout_map.get_free_placement_for_item(item, false)
		if placement.cell == Vector2i(-1, -1):
			return InventoryOperationDecision.reject(&"relayout_unavailable")
		var target_cells := layout_map.get_occupy_cells_for_item_with_dir(
			item, placement.dir, placement.cell
		)
		if !layout_map.try_occupy(item, target_cells):
			return InventoryOperationDecision.reject(&"relayout_unavailable")
		candidate.layout_targets[item] = {"cell": placement.cell, "dir": placement.dir}
		var previous_cell := inventory.occupy_map.get_item_center_cell(item)
		if previous_cell != placement.cell:
			var move := InventoryOperationEffect.create(
				InventoryOperationEffect.Type.CHANGE_POSITION, item, inventory
			)
			move.cell_before = previous_cell
			move.cell_after = placement.cell
			candidate.add_effect(move)
		if item.dir != placement.dir:
			var rotate := InventoryOperationEffect.create(
				InventoryOperationEffect.Type.CHANGE_ROTATION, item, inventory
			)
			rotate.dir_before = item.dir
			rotate.dir_after = placement.dir
			candidate.add_effect(rotate)
	return InventoryOperationDecision.allow(candidate)


static func _capture(
	candidate: InventoryOperationPlan, inventory: InventoryData, item: ItemInstanceData
) -> void:
	candidate.capture_inventory(inventory)
	candidate.capture_item(item, inventory if inventory != null and inventory.has_item_instance(item) else null)


static func _add_quantity_effect(
	candidate: InventoryOperationPlan,
	item: ItemInstanceData,
	inventory: InventoryData,
	before: int,
	after: int
) -> void:
	var effect := InventoryOperationEffect.create(
		InventoryOperationEffect.Type.CHANGE_QUANTITY, item, inventory
	)
	effect.quantity_before = before
	effect.quantity_after = after
	candidate.add_effect(effect)


static func _evaluate_endpoint(candidate: InventoryOperationPlan, endpoint: InventoryOperationEndpoint, provider_type: InventoryOperationRuleContext.ProviderType) -> InventoryOperationDecision:
	var effects: Array[InventoryOperationEffect] = []
	for effect in candidate.effects:
		if effect.inventory == endpoint.inventory or (effect.inventory == null and endpoint == candidate.request.operation_context.target_endpoint):
			effects.append(effect)
	if effects.is_empty():
		effects.append(null)
	for rule in endpoint.policy.rules:
		for effect in effects:
			var context := _make_context(candidate, provider_type)
			context.endpoint = endpoint
			context.provider_inventory = endpoint.inventory
			context.effect = effect
			var decision := _evaluate_rule(rule, context)
			if not decision.allowed:
				return decision
	return InventoryOperationDecision.allow(candidate)


static func _make_context(
	candidate: InventoryOperationPlan,
	provider_type: InventoryOperationRuleContext.ProviderType
) -> InventoryOperationRuleContext:
	var context := InventoryOperationRuleContext.new()
	context.request = candidate.request
	context.plan = candidate
	context.provider_type = provider_type
	context.view = candidate.view
	context.after_view = candidate.after_view
	context.transaction_view = candidate.transaction_view
	context.transaction_effects = candidate.transaction_effects
	return context


static func _evaluate_rule(
	rule: InventoryOperationRule, context: InventoryOperationRuleContext
) -> InventoryOperationDecision:
	if rule == null:
		return InventoryOperationDecision.reject(&"invalid_inventory_rule")
	var decision := rule.evaluate(context)
	if decision == null:
		return InventoryOperationDecision.reject(&"invalid_inventory_rule")
	if !decision.allowed:
		decision.provider_type = context.provider_type
		if context.provider_part != null:
			decision.provider = context.provider_part
		else:
			decision.provider = context.provider_inventory
		if decision.provider == null:
			decision.provider = context.provider_item
	return decision

## 通用 State 结果必须覆盖相同键／类型，不得偷偷修改占格。
static func _build_state_update(candidate: InventoryOperationPlan) -> InventoryOperationDecision:
	var request := candidate.request
	if not request.source_inventory.has_item_instance(request.item):
		return InventoryOperationDecision.reject(&"source_item_missing")
	if request.state_results.size() != request.item.instance_states.size():
		return InventoryOperationDecision.reject(&"invalid_state_results")
	var keys: Dictionary = {}
	for old in request.item.instance_states:
		keys[old.state_key] = old.get_script()
	for state in request.state_results:
		if state == null or not keys.has(state.state_key) or keys[state.state_key] != state.get_script():
			return InventoryOperationDecision.reject(&"invalid_state_results")
		keys.erase(state.state_key)
		var copy := state.duplicate_for_operation()
		if copy == null or copy == state or copy.state_key != state.state_key or copy.get_script() != state.get_script():
			return InventoryOperationDecision.reject(&"invalid_state_results")
		candidate.prepared_state_results.append(copy)
	candidate.requested_states_signature = InventoryOperationFingerprint.of(request.state_results)
	var projected := request.item.duplicate_for_operation()
	projected.instance_states = candidate.prepared_state_results
	if projected.get_local_cells() != request.item.get_local_cells():
		return InventoryOperationDecision.reject(&"state_update_changes_occupancy")
	_capture(candidate, request.source_inventory, request.item)
	candidate.add_effect(InventoryOperationEffect.create(InventoryOperationEffect.Type.CHANGE_STATES, request.item, request.source_inventory))
	return InventoryOperationDecision.allow(candidate)
