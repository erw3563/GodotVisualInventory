class_name InventoryHostTransferExecutor
extends RefCounted
## 源中心的双端贡献编排；同一库存计划一次提交。
static func execute(source: InventoryHost, target: InventoryHost, item: ItemInstanceData, quantity: int = -1, binding_check: Callable = Callable()) -> InventoryOperationResult:
	var source_contributor := source.get_transfer_contributor()
	var target_contributor := target.get_transfer_contributor()
	if source_contributor == null:
		return InventoryOperationResult.failed(&"inventory_transfer_source_feature_missing")
	if target_contributor == null:
		return InventoryOperationResult.failed(&"inventory_transfer_target_feature_missing")
	var source_endpoint := source.get_operation_endpoint()
	var target_endpoint := target.get_operation_endpoint()
	var operation := InventoryOperationContext.between(source_endpoint, target_endpoint)
	var fingerprint := operation.fingerprint()
	var decision := InventoryTransferOperations.plan_transfer_item(operation, source.get_inventory_data(), target.get_inventory_data(), item, quantity)
	if not decision.allowed:
		return InventoryOperationResult.failed(decision.reason_key, decision.plan)
	var contributions: Array[InventoryHostTransferContribution] = []
	var settlements: Array[InventoryOperationSettlementParticipant] = []
	for direction in [InventoryHostTransferContext.Direction.OUTGOING, InventoryHostTransferContext.Direction.INCOMING]:
		var context := InventoryHostTransferContext.new()
		context.source_host = source
		context.target_host = target
		context.operation_context = operation
		context.plan = decision.plan
		context.requested_quantity = quantity
		context.direction = direction
		var contributor := source_contributor if direction == InventoryHostTransferContext.Direction.OUTGOING else target_contributor
		var contribution := contributor.prepare(context)
		if contribution == null:
			return InventoryOperationResult.failed(&"inventory_transfer_contribution_missing", decision.plan)
		var reason := contribution.validate()
		if reason != &"":
			return InventoryOperationResult.failed(reason, decision.plan)
		contributions.append(contribution)
		settlements.append_array(contribution.settlements)
	var revalidate := func() -> StringName:
		if binding_check.is_valid() and not binding_check.call():
			return &"inventory_transfer_binding_stale"
		if not is_instance_valid(source) or not is_instance_valid(target):
			return &"inventory_transfer_endpoint_stale"
		if source.get_operation_endpoint() != source_endpoint or target.get_operation_endpoint() != target_endpoint or operation.fingerprint() != fingerprint:
			return &"inventory_transfer_endpoint_stale"
		for contribution in contributions:
			var reason := contribution.validate()
			if reason != &"":
				return reason
		return &""
	return InventoryOperationSettlementParticipant.commit(decision.plan, settlements, revalidate)
