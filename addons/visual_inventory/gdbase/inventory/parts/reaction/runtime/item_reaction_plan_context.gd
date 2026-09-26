class_name ItemReactionPlanContext
extends RefCounted
## 每次规则执行独占；只暴露查询和追加请求，不拥有提交入口。
var source: ItemInstanceData
var random: RandomNumberGenerator
var trigger_type: int = -1
var plan_result: ItemReactionPlanResult
var protected_counter_item: ItemInstanceData
var protected_counter_key: String = ""
var _transaction: InventoryOperationTransaction
var view: InventoryOperationView:
	get:
		return _transaction.view

func append(type: InventoryOperationRequest.Type, item: ItemInstanceData, quantity: int = -1, cell: Vector2i = Vector2i(-1, -1), shape_result: ItemInstanceState = null, states: Array[ItemInstanceState] = []) -> ItemReactionPlanResult:
	if item == protected_counter_item and type == InventoryOperationRequest.Type.UPDATE_STATES:
		for state in states:
			if state != null and state.state_key == protected_counter_key and InventoryOperationFingerprint.of(state) != InventoryOperationFingerprint.of(view.get_item(item).get_state_by_key(protected_counter_key)):
				_transaction.reason_key = &"trigger_counter_write_forbidden"
				return ItemReactionPlanResult.failed(_transaction.reason_key)
	var request := InventoryOperationRequest.create(_transaction.operation_context, type, item)
	if type in [InventoryOperationRequest.Type.PLACE_AT, InventoryOperationRequest.Type.ADD_WITH_MERGE, InventoryOperationRequest.Type.ADD_WITHOUT_MERGE]:
		request.target_inventory = _transaction.inventory
	else:
		request.source_inventory = _transaction.inventory
		if type != InventoryOperationRequest.Type.CONSUME:
			request.target_inventory = _transaction.inventory
	request.requested_quantity = quantity
	request.target_cell = cell
	request.shape_result = shape_result
	request.state_results = states
	var decision := _transaction.append(request)
	return ItemReactionPlanResult.planned() if decision.allowed else ItemReactionPlanResult.failed(decision.reason_key)

func fork() -> ItemReactionPlanContext:
	var child := ItemReactionPlanContext.new()
	child.source = source
	child.random = random
	child.trigger_type = trigger_type
	child.protected_counter_item = protected_counter_item
	child.protected_counter_key = protected_counter_key
	child._transaction = _transaction.fork()
	return child

func adopt(child: ItemReactionPlanContext) -> void:
	_transaction = child._transaction
