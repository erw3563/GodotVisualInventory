class_name ShopTradeProcessor
extends RefCounted
## 商店计价与支付编排，消费同一份库存 Plan。
static func execute(request: InventoryOperationRequest, source_session: ShopTradeSession = null, target_session: ShopTradeSession = null) -> InventoryOperationResult:
	var decision := InventoryOperationPlanner.plan(request)
	if not decision.allowed:
		return InventoryOperationResult.failed(decision.reason_key, decision.plan)
	var prepared := prepare_payments(decision.plan, source_session, target_session)
	if prepared.reason != &"":
		return InventoryOperationResult.failed(prepared.reason, decision.plan)
	var payments: Array[Dictionary] = []
	payments.assign(prepared.payments)
	return commit_with_payments(decision.plan, payments)

## 根据显式提供的本端会话生成冻结的钱包增减条目。
static func prepare_payments(plan: InventoryOperationPlan, source_session: ShopTradeSession = null, target_session: ShopTradeSession = null) -> Dictionary:
	var take_entries := _collect_take_entries(plan, source_session)
	var put_entries := _collect_put_entries(plan, target_session)
	if not _can_apply_entries(source_session, take_entries, true) or not _can_apply_entries(target_session, put_entries, false):
		return {"reason": &"shop_payment_rejected", "payments": []}
	var payments: Array[Dictionary] = []
	for entry in take_entries:
		payments.append({"wallet": source_session.customer_wallet, "delta": source_session.preview_take_cost(entry.item, entry.amount)})
	for entry in put_entries:
		var calculator := ShopInteractionCostCalculator.new()
		calculator.apply_from_policy(target_session.policy)
		payments.append({"wallet": target_session.customer_wallet,
			"delta": calculator.get_put_transaction_signed_for_wallet(entry.item.get_item_data(), entry.amount)})
	return {"reason": &"", "payments": payments}

static func commit_with_payments(plan: InventoryOperationPlan, payments: Array[Dictionary]) -> InventoryOperationResult:
	var participant := ShopTransferSettlementParticipant.new()
	participant.payments = payments
	var participants: Array[InventoryOperationSettlementParticipant] = [participant]
	return InventoryOperationSettlementParticipant.commit(plan, participants)

static func _collect_take_entries(
	plan: InventoryOperationPlan, session: ShopTradeSession
) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if session == null or !session.is_take_trade_active():
		return entries
	for effect in plan.effects:
		if effect.type != InventoryOperationEffect.Type.LEAVE_INVENTORY:
			continue
		if effect.inventory != session.stock_inventory:
			continue
		var amount := effect.quantity_before
		if amount <= 0:
			amount = effect.item.get_item_num()
		entries.append({"item": effect.item, "amount": amount})
	return entries


static func _collect_put_entries(
	plan: InventoryOperationPlan, session: ShopTradeSession
) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if session == null or !session.is_put_trade_active():
		return entries
	for effect in plan.effects:
		if effect.inventory != session.stock_inventory:
			continue
		if effect.type == InventoryOperationEffect.Type.ENTER_INVENTORY:
			var amount := effect.quantity_after
			if amount <= 0:
				amount = effect.item.get_item_num()
			entries.append({"item": effect.item, "amount": amount})
		elif effect.type == InventoryOperationEffect.Type.CHANGE_QUANTITY \
				and effect.quantity_after > effect.quantity_before:
			entries.append({
				"item": effect.item,
				"amount": effect.quantity_after - effect.quantity_before,
			})
	return entries


static func _can_apply_entries(
	session: ShopTradeSession, entries: Array[Dictionary], is_take: bool
) -> bool:
	if session == null:
		return true
	for entry in entries:
		var item := entry.item as ItemInstanceData
		var amount := int(entry.amount)
		if is_take:
			if !session.can_afford_take(item, amount):
				return false
		elif !session.can_afford_put(item, amount):
			return false
	return true

