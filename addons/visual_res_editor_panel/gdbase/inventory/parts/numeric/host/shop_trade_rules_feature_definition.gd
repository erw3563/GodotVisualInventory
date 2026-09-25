@tool
class_name ShopTradeRulesFeatureDefinition
extends InventoryHostFeatureDefinition
## 显式交易规则提供者；没有输入动作。策略为空沿用标准商人货架。
@export var trade_policy: ShopTradePolicy

func create_assembly(context: InventoryHostFeatureContext) -> InventoryHostFeatureAssembly:
	var assembly := ShopTradeRulesFeatureAssembly.new()
	assembly.policy_template = trade_policy if trade_policy != null else ShopTradePolicy.make_merchant_shelf()
	assembly.session = ShopTradeSession.new()
	context.mount_owned_node(assembly, assembly.session)
	return assembly
