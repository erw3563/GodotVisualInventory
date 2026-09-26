class_name ItemNumericOperations
extends RefCounted
## 数值 Consumer 共用的只读查询与 UPDATE_STATES 纯规划。
static func read(item: ItemInstanceData, key: StringName) -> Dictionary:
	if item == null or item.item_data == null:
		return {"reason_key": &"numeric_item_missing"}
	var part := item.item_data.get_type_part(ItemNumericPart.PART_TYPE) as ItemNumericPart
	if part == null or part.validate_configuration() != &"":
		return {"reason_key": &"numeric_part_missing_or_invalid"}
	var entry := part.find_entry(key)
	if entry == null:
		return {"reason_key": &"numeric_value_missing"}
	if entry.storage_mode == ItemNumericEntry.StorageMode.FIXED:
		return {"reason_key": &"", "value": entry.typed(entry.value)}
	var state := part.resolve_state(item)
	if state == null or not state.values.has(key) or not state.is_valid_instance_state():
		return {"reason_key": &"invalid_numeric_state"}
	var value: Variant = state.values[key]
	if typeof(value) != (TYPE_INT if entry.number_type == ItemNumericEntry.NumberType.INTEGER else TYPE_FLOAT) or not entry.accepts_number(value):
		return {"reason_key": &"invalid_numeric_value"}
	return {"reason_key": &"", "value": value}

static func plan_change(view: InventoryOperationView, item: ItemInstanceData, key: StringName, amount: Variant, relative: bool = true) -> Dictionary:
	if view == null or item == null or not view.has_item(item):
		return {"reason_key": &"source_item_missing"}
	var projected := view.get_item(item)
	var current := read(projected, key)
	if current.reason_key != &"":
		return current
	var part := projected.item_data.get_type_part(ItemNumericPart.PART_TYPE) as ItemNumericPart
	var entry := part.find_entry(key)
	if entry.storage_mode != ItemNumericEntry.StorageMode.INSTANCE:
		return {"reason_key": &"numeric_value_is_fixed"}
	if not entry.accepts_number(amount):
		return {"reason_key": &"invalid_numeric_amount"}
	var next: Variant = current.value + amount if relative else amount
	if not entry.accepts_number(next):
		return {"reason_key": &"numeric_overflow"}
	var state := part.resolve_state(projected).duplicate_for_operation() as ItemNumericState
	state.values[key] = entry.typed(next)
	if not state.reconcile_with_part(part):
		return {"reason_key": &"invalid_numeric_state"}
	var states: Array[ItemInstanceState] = []
	for existing in projected.instance_states:
		states.append(state if existing.state_key == state.state_key else existing.duplicate_for_operation())
	return {"reason_key": &"", "states": states}

static func prepare(context: InventoryOperationContext, inventory: InventoryData, item: ItemInstanceData, key: StringName, amount: Variant, relative: bool = true) -> InventoryOperationTransaction:
	var tx := InventoryOperationTransaction.begin(context, inventory)
	if tx.reason_key != &"":
		return tx
	var change := plan_change(tx.view, item, key, amount, relative)
	if change.reason_key != &"":
		tx.reason_key = change.reason_key
		return tx
	var request := InventoryOperationRequest.create(context, InventoryOperationRequest.Type.UPDATE_STATES, item)
	request.source_inventory = inventory
	request.target_inventory = inventory
	request.state_results = change.states
	tx.append(request)
	return tx

static func adjust(context: InventoryOperationContext, inventory: InventoryData, item: ItemInstanceData, key: StringName, delta: Variant) -> InventoryOperationResult:
	return InventoryOperationCommitter.commit_transaction(prepare(context, inventory, item, key, delta))

static func set_value(context: InventoryOperationContext, inventory: InventoryData, item: ItemInstanceData, key: StringName, value: Variant) -> InventoryOperationResult:
	return InventoryOperationCommitter.commit_transaction(prepare(context, inventory, item, key, value, false))
