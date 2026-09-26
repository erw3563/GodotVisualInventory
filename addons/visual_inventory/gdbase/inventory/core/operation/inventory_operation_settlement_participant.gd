@abstract
class_name InventoryOperationSettlementParticipant
extends RefCounted
## 同次操作的外域结算批次协议。
@abstract func batch_key() -> StringName
@abstract func merge_from(other: InventoryOperationSettlementParticipant) -> bool
@abstract func validate() -> StringName
@abstract func apply_silent() -> bool
@abstract func rollback() -> void
@abstract func notify_committed() -> void

static func commit(plan: InventoryOperationPlan, participants: Array[InventoryOperationSettlementParticipant], revalidate: Callable = Callable()) -> InventoryOperationResult:
	var batches: Array[InventoryOperationSettlementParticipant] = []
	var by_key: Dictionary = {}
	for participant in participants:
		var key := participant.batch_key()
		if key == &"":
			return InventoryOperationResult.failed(&"invalid_settlement_batch", plan)
		if by_key.has(key):
			if not by_key[key].merge_from(participant):
				return InventoryOperationResult.failed(&"settlement_batch_conflict", plan)
		else:
			by_key[key] = participant
			batches.append(participant)
	for batch in batches:
		var reason := batch.validate()
		if reason != &"":
			return InventoryOperationResult.failed(reason, plan)
	if revalidate.is_valid():
		var reason: StringName = revalidate.call()
		if reason != &"":
			return InventoryOperationResult.failed(reason, plan)
	var applied: Array[InventoryOperationSettlementParticipant] = []
	for batch in batches:
		applied.append(batch)
		if not batch.apply_silent():
			applied.reverse()
			for previous in applied:
				previous.rollback()
			return InventoryOperationResult.failed(&"settlement_apply_failed", plan)
	var result := InventoryOperationCommitter.commit(plan)
	if not result.success:
		applied.reverse()
		for batch in applied:
			batch.rollback()
		return result
	for batch in batches:
		batch.notify_committed()
	return result
