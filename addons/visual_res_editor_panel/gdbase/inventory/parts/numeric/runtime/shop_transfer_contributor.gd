class_name ShopTransferContributor
extends InventoryHostTransferContributor
## 消费转移按本端方向向所属 Host 的规则申请结算。
func prepare(context: InventoryHostTransferContext) -> InventoryHostTransferContribution:
	var result := super.prepare(context)
	if result.reason != &"":
		return result
	var host := get_host()
	var rules := host.get_feature_assembly(ShopTradeRulesFeatureDefinition) as ShopTradeRulesFeatureAssembly
	if rules == null or not is_instance_valid(rules.session) or not rules.session.active:
		return InventoryHostTransferContribution.rejected(&"shop_session_missing")
	var session := rules.session
	if session.stock_inventory != host.get_inventory_data() or session.customer_wallet == null:
		return InventoryHostTransferContribution.rejected(&"shop_session_missing")
	var outgoing := context.direction == InventoryHostTransferContext.Direction.OUTGOING
	var prepared := ShopTradeProcessor.prepare_payments(context.plan, session if outgoing else null, null if outgoing else session)
	if prepared.reason != &"":
		return InventoryHostTransferContribution.rejected(prepared.reason)
	var payment := ShopTransferSettlementParticipant.new()
	payment.payments.assign(prepared.payments)
	result.settlements.append(payment)
	var previous_check := result.validity_check
	var fingerprint := session.configuration_fingerprint()
	var wallet := session.customer_wallet
	var balance := wallet.value
	var currency := wallet.type
	result.validity_check = func() -> StringName:
		var reason: StringName = previous_check.call()
		if reason != &"":
			return reason
		if host.get_feature_assembly(ShopTradeRulesFeatureDefinition) != rules or not is_instance_valid(session) or not session.active:
			return &"shop_session_stale"
		if wallet.value != balance or wallet.type != currency:
			return &"shop_session_stale"
		return &"" if session.configuration_fingerprint() == fingerprint else &"shop_session_stale"
	return result
