@tool
@abstract
class_name ShopInputFeatureDefinition
extends InventoryHostFeatureDefinition
## 输入消费功能必须在同一列表中显式配置于规则之后。
func _init() -> void:
	input_priority = 100

func validate_configuration(features: Array[InventoryHostFeatureDefinition]) -> StringName:
	var rules_index := -1
	for index in features.size():
		if features[index] is ShopTradeRulesFeatureDefinition:
			rules_index = index
			break
	if rules_index < 0:
		return &"shop_input_requires_trade_rules"
	if rules_index >= features.find(self):
		return &"shop_trade_rules_must_precede_input"
	return &""
