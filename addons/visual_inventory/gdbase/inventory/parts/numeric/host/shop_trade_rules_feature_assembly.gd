class_name ShopTradeRulesFeatureAssembly
extends InventoryHostFeatureAssembly
## 持有本 Host 的交易会话与策略，供消费功能显式借用。
var session: ShopTradeSession
var policy_template: ShopTradePolicy

func refresh(context: InventoryHostFeatureContext) -> bool:
	var dependency := context.host.get_feature_dependency(ShopTradeRulesFeatureDefinition)
	if dependency != null and not dependency is ShopInventoryBinding:
		push_error("shop_binding_type_invalid")
		return false
	var binding := dependency as ShopInventoryBinding
	var customer: InventoryData = binding.customer_inventory if binding != null else null
	var customer_host: InventoryHost = context.host.transfer_target_host
	if is_instance_valid(customer_host):
		if customer != null and customer != customer_host.get_inventory_data():
			push_error("shop_customer_inventory_mismatch")
			return false
		customer = customer_host.get_inventory_data()
	if customer != null and customer == context.inventory_data:
		push_error("shop_customer_is_stock")
		return false
	session.stock_inventory = null
	session.customer_wallet = binding.customer_wallet if binding != null else null
	var policy := binding.trade_policy if binding != null and binding.trade_policy != null else policy_template
	session.policy = policy.duplicate(true) as ShopTradePolicy
	session.stock_inventory = context.inventory_data
	session.active = true
	session.revision += 1
	return true

func teardown() -> void:
	if is_instance_valid(session):
		session.active = false
		session.revision += 1
		session.stock_inventory = null
		session.customer_wallet = null
	super.teardown()
