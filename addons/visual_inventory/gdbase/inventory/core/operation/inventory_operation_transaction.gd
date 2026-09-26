class_name InventoryOperationTransaction
extends RefCounted
## 单库存操作工作区。只规划隔离投影；发布仅由 InventoryOperationCommitter 完成。
var operation_context: InventoryOperationContext
var policy_signature: int
var inventory: InventoryData
var view: InventoryOperationView
var baseline: InventoryOperationPlan
var steps: Array[InventoryOperationRequest] = []
var step_signatures: Array[int] = []
var rule_plans: Array[InventoryOperationPlan] = []
var used := false
var reason_key: StringName
var _projection: InventoryData
var _actual_to_virtual: Dictionary = {}
var _virtual_to_actual: Dictionary = {}
var _guards: Dictionary = {}
var _inventory_signature: int
var _new_items: Array[ItemInstanceData] = []
var _new_snapshots: Dictionary = {}
var _state_changed: Dictionary = {}
var _replace_all_states: Dictionary = {}
var _prepared_states: Dictionary = {}

static func begin(context: InventoryOperationContext, target: InventoryData) -> InventoryOperationTransaction:
	var tx := InventoryOperationTransaction.new()
	if target == null or target.occupy_map == null:
		tx.reason_key = &"invalid_transaction_inventory"
		return tx
	tx.operation_context = context
	if context == null or context.validate(target, target) != &"":
		tx.reason_key = &"invalid_transaction_context"
		return tx
	tx.policy_signature = context.fingerprint()
	tx.inventory = target
	tx.baseline = InventoryOperationPlan.new()
	tx.baseline.capture_inventory(target)
	for item in target.get_item_instances():
		tx.baseline.capture_item(item, target)
	tx._inventory_signature = tx._capture_inventory_signature()
	tx._projection = InventoryData.new()
	tx._projection.set_block_signals(true)
	tx._projection.occupy_map = target.occupy_map.duplicate(false)
	# duplicate(false) copies containers but retains item references; detach all indexes first.
	tx._projection.occupy_map.occupied_cells = {}
	tx._projection.occupy_map.occupant_to_cells = {}
	tx._projection.occupy_map.occupant_to_center_cell = {}
	tx._projection.occupy_map.placed_item_instances = []
	tx._projection.occupy_map.unplaced_item_instances = []
	tx._projection.occupy_map.set_block_signals(true)
	for item in target.get_item_instances():
		var copy := item.duplicate_for_operation()
		copy.set_block_signals(true)
		tx._actual_to_virtual[item] = copy
		tx._virtual_to_actual[copy] = item
		InventoryOperationCommitter.seed_projection(tx._projection, copy, target.occupy_map.get_item_center_cell(item))
	tx.view = InventoryOperationView.new()
	tx.view._inventory = tx._projection
	tx.view._actual_to_virtual = tx._actual_to_virtual
	tx.view._virtual_to_actual = tx._virtual_to_actual
	return tx

func guard(resource: Resource) -> void:
	if resource != null and not _guards.has(resource):
		_guards[resource] = InventoryOperationFingerprint.of(resource)

func _capture_inventory_signature() -> int:
	return InventoryOperationFingerprint.of([inventory.occupy_map, inventory.item_instances])

func validate_fresh() -> StringName:
	if used:
		return &"operation_plan_already_used"
	if reason_key != &"":
		return reason_key
	if operation_context == null or operation_context.fingerprint() != policy_signature:
		return &"stale_operation_policy"
	if inventory == null or _capture_inventory_signature() != _inventory_signature:
		return &"stale_operation_plan"
	# baseline has no operation request; freshness helper only needs a non-null request.
	var check := baseline
	check.request = InventoryOperationRequest.new()
	var reason := InventoryOperationCommitter._validate_fresh(check)
	if reason != &"":
		return reason
	for resource in _guards:
		if InventoryOperationFingerprint.of(resource) != _guards[resource]:
			return &"stale_operation_plan"
	for item in _new_snapshots:
		if InventoryOperationFingerprint.of(item) != _new_snapshots[item]:
			return &"stale_operation_plan"
	return &""

func append(request: InventoryOperationRequest) -> InventoryOperationDecision:
	if reason_key != &"":
		return InventoryOperationDecision.reject(reason_key)
	if request == null or request.item == null or steps.size() >= 512:
		return _reject(&"invalid_transaction_request")
	if request.operation_context != operation_context:
		return _reject(&"transaction_context_mismatch")
	if (request.source_inventory != null and request.source_inventory != inventory) or (request.target_inventory != null and request.target_inventory != inventory):
		return _reject(&"transaction_requires_single_inventory")
	if request.type not in [InventoryOperationRequest.Type.CONSUME, InventoryOperationRequest.Type.PLACE_AT, InventoryOperationRequest.Type.ADD_WITH_MERGE, InventoryOperationRequest.Type.ADD_WITHOUT_MERGE, InventoryOperationRequest.Type.MOVE_WITHIN, InventoryOperationRequest.Type.RESHAPE, InventoryOperationRequest.Type.UPDATE_STATES]:
		return _reject(&"unsupported_transaction_operation")
	if not _actual_to_virtual.has(request.item):
		if request.source_inventory != null:
			return _reject(&"source_item_missing")
		_new_items.append(request.item)
		_new_snapshots[request.item] = InventoryOperationFingerprint.of(request.item)
		var copy := request.item.duplicate_for_operation()
		copy.set_block_signals(true)
		_actual_to_virtual[request.item] = copy
		_virtual_to_actual[copy] = request.item
	var projected := copy_request(request)
	projected.item = _actual_to_virtual[request.item]
	projected.source_inventory = _projection if request.source_inventory != null else null
	projected.target_inventory = _projection if request.target_inventory != null else null
	var valid := InventoryOperationPlanner._validate_request(projected, false)
	if not valid.allowed:
		return _reject(valid.reason_key)
	var candidate := InventoryOperationPlan.new()
	candidate.request = projected
	var built := InventoryOperationPlanner._build_plan(candidate)
	if not built.allowed:
		return _reject(built.reason_key)
	var mapped := _map_plan(candidate, request)
	var prepare := InventoryOperationCommitter._prepare_stack_plans(candidate)
	if prepare != &"":
		return _reject(prepare)
	if not InventoryOperationCommitter._commit_by_type(candidate):
		return _reject(&"projection_commit_failed")
	_projection.ensure_occupancy_synced()
	mapped.after_view = _snapshot_view()
	for stack_plan in candidate.stack_plans:
		_state_changed[_virtual_to_actual.get(stack_plan.target_item, stack_plan.target_item)] = true
		_replace_all_states[_virtual_to_actual.get(stack_plan.target_item, stack_plan.target_item)] = true
		if stack_plan.source_item != null:
			_state_changed[_virtual_to_actual.get(stack_plan.source_item, stack_plan.source_item)] = true
			_replace_all_states[_virtual_to_actual.get(stack_plan.source_item, stack_plan.source_item)] = true
	if request.type in [InventoryOperationRequest.Type.RESHAPE, InventoryOperationRequest.Type.UPDATE_STATES]:
		_state_changed[request.item] = true
	var rules := InventoryOperationPlanner.evaluate_rules(mapped)
	if not rules.allowed:
		return _reject(rules.reason_key)
	steps.append(copy_request(request))
	rule_plans.append(mapped)
	step_signatures.append(_signature())
	return InventoryOperationDecision.allow(mapped)

func _reject(reason: StringName) -> InventoryOperationDecision:
	reason_key = reason
	return InventoryOperationDecision.reject(reason)

func _snapshot_view() -> InventoryOperationView:
	var snapshot := InventoryOperationTransaction.begin(InventoryOperationContext.system(), _projection)
	var result := snapshot.view
	var a_to_v: Dictionary = {}
	var v_to_a: Dictionary = {}
	for actual in _actual_to_virtual:
		var projected: ItemInstanceData = _actual_to_virtual[actual]
		if snapshot._actual_to_virtual.has(projected):
			var copied: ItemInstanceData = snapshot._actual_to_virtual[projected]
			a_to_v[actual] = copied
			v_to_a[copied] = actual
		else:
			a_to_v[actual] = projected.duplicate_for_operation()
	result._actual_to_virtual = a_to_v
	result._virtual_to_actual = v_to_a
	return result

func _map_plan(candidate: InventoryOperationPlan, request: InventoryOperationRequest) -> InventoryOperationPlan:
	var result := InventoryOperationPlan.new()
	result.request = copy_request(request)
	result.policy_signature = policy_signature
	result.actual_quantity = candidate.actual_quantity
	result.view = _snapshot_view()
	for effect in candidate.effects:
		var mapped := InventoryOperationEffect.new()
		for property in effect.get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				mapped.set(property.name, effect.get(property.name))
		mapped.item = _virtual_to_actual.get(effect.item, effect.item)
		mapped.inventory = inventory if effect.inventory != null else null
		result.effects.append(mapped)
	return result

func _signature() -> int:
	var facts: Array = []
	for actual in _actual_to_virtual:
		var item: ItemInstanceData = _actual_to_virtual[actual]
		facts.append([item.num, item.dir, item.instance_states, _projection.has_item_instance(item), _projection.occupy_map.get_item_center_cell(item)])
	facts.append(_projection.occupy_map.cells)
	return InventoryOperationFingerprint.of(facts)

func replay() -> InventoryOperationTransaction:
	var fresh := begin(operation_context, inventory)
	for request in steps:
		var decision := fresh.append(request)
		if not decision.allowed:
			return fresh
		if fresh.step_signatures[-1] != step_signatures[fresh.steps.size() - 1]:
			fresh.reason_key = &"stale_operation_plan"
			return fresh
	return fresh

func fork() -> InventoryOperationTransaction:
	var child := replay()
	child._guards = _guards.duplicate()
	return child

static func copy_request(source: InventoryOperationRequest) -> InventoryOperationRequest:
	var result := InventoryOperationRequest.new()
	for property in source.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			result.set(property.name, source.get(property.name))
	if source.shape_result != null:
		result.shape_result = source.shape_result.duplicate_for_operation()
	result.state_results = []
	for state in source.state_results:
		result.state_results.append(state.duplicate_for_operation() if state != null else null)
	return result
