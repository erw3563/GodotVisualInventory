class_name ShopTransferFeatureAssembly
extends InventoryHostFeatureAssembly
## 持有本 Host 的消费转移贡献者与快捷输入处理器。
func _init() -> void:
	transfer_contributor = ShopTransferContributor.new()

func refresh(context: InventoryHostFeatureContext) -> bool:
	var rules := context.host.get_feature_assembly(ShopTradeRulesFeatureDefinition) as ShopTradeRulesFeatureAssembly
	if rules == null or not is_instance_valid(rules.session):
		return false
	return super.refresh(context)
