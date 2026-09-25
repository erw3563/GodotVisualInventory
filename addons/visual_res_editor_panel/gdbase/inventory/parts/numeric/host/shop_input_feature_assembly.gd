class_name ShopInputFeatureAssembly
extends InventoryHostFeatureAssembly
var processor: ShopInputActionProcessor

func refresh(context: InventoryHostFeatureContext) -> bool:
	var rules := context.host.get_feature_assembly(ShopTradeRulesFeatureDefinition) as ShopTradeRulesFeatureAssembly
	if rules == null or not is_instance_valid(rules.session):
		return false
	processor.session = rules.session
	processor.host = weakref(context.host)
	return true

func teardown() -> void:
	if processor != null:
		processor.session = null
		processor.host = null
	super.teardown()
