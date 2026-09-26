@abstract
class_name ShopInputActionProcessor
extends InventoryInputActionProcessor
## 消费处理器共用会话校验；动作适用性须先判断，避免另一项动作被误拒绝。
var session: ShopTradeSession
var host: WeakRef

func has_live_session(context: InventoryInputActionContext) -> bool:
	var owner_host := host.get_ref() as InventoryHost if host != null else null
	if not is_instance_valid(owner_host) or not is_instance_valid(session):
		return false
	var rules := owner_host.get_feature_assembly(ShopTradeRulesFeatureDefinition) as ShopTradeRulesFeatureAssembly
	return rules != null and rules.session == session and session.active \
		and session.stock_inventory == context.inventory and session.customer_wallet != null

func operation_result(success: bool) -> InventoryInputActionResult:
	return InventoryInputActionResult.handled() if success else InventoryInputActionResult.rejected(&"shop_operation_rejected")
