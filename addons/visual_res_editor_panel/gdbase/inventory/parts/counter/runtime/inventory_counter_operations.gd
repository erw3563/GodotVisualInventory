class_name InventoryCounterOperations
extends RefCounted
## 外部与反应共用纯规划；不依赖 Reaction。
const MAX_VALUE: int = 9223372036854775807

static func plan_change(view: InventoryOperationView, item: ItemInstanceData, key: String, delta: int) -> InventoryCounterChange:
	var result := InventoryCounterChange.new()
	if delta == 0:
		result.reason_key = &"counter_delta_zero"
		return result
	if view == null or item == null or not view.has_item(item):
		result.reason_key = &"source_item_missing"
		return result
	var projected := view.get_item(item)
	result.reason_key = ItemCounterPart.validate_item(projected.item_data)
	if result.reason_key != &"":
		return result
	var part := ItemCounterPart.find(projected.item_data, key)
	if part == null:
		result.reason_key = &"counter_missing"
		return result
	var state := part.resolve_state(projected)
	if state == null or not state.reconcile_with_part(part):
		result.reason_key = &"invalid_counter_state"
		return result
	if delta > 0 and state.current_value > MAX_VALUE - delta:
		result.reason_key = &"counter_overflow"
		return result
	var next := 0 if delta < -state.current_value else state.current_value + delta
	if next != state.current_value:
		result.state = state.duplicate_state() as ItemCounterState
		result.state.current_value = next
		for existing in projected.instance_states:
			result.states.append(result.state if existing.state_key == key else existing.duplicate_state())
	return result

static func prepare(operation_context: InventoryOperationContext, inventory: InventoryData, item: ItemInstanceData, key: String, delta: int) -> InventoryOperationTransaction:
	var tx := InventoryOperationTransaction.begin(operation_context, inventory)
	if tx.reason_key != &"":
		return tx
	var change := plan_change(tx.view, item, key, delta)
	if change.reason_key != &"":
		tx.reason_key = change.reason_key
	elif change.state != null:
		var request := InventoryOperationRequest.create(operation_context, InventoryOperationRequest.Type.UPDATE_STATES, item)
		request.source_inventory = inventory
		request.target_inventory = inventory
		request.state_results = change.states
		tx.append(request)
	return tx

static func adjust(operation_context: InventoryOperationContext, inventory: InventoryData, item: ItemInstanceData, key: String, delta: int) -> InventoryOperationResult:
	return InventoryOperationCommitter.commit_transaction(prepare(operation_context, inventory, item, key, delta))
