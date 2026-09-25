@tool
class_name InventoryOperationRulesFeatureDefinition
extends InventoryHostFeatureDefinition
## 当前 Host 选择遵守的物品标签；输入能力独立配置。
@export var respect_no_take_tag := false
@export var respect_no_place_tag := false
@export var respect_no_consume_tag := false
@export var respect_infinite_supply_tag := true

func build_operation_policy() -> InventoryOperationPolicy:
	var policy := InventoryOperationPolicy.new()
	if respect_no_take_tag:
		policy.rules.append(ItemTagOperationRule.create(InventoryItemTags.NO_TAKE))
	if respect_no_place_tag:
		policy.rules.append(ItemTagOperationRule.create(InventoryItemTags.NO_PLACE))
	if respect_no_consume_tag:
		policy.rules.append(ItemTagOperationRule.create(InventoryItemTags.NO_CONSUME))
	return policy

func create_assembly(_context: InventoryHostFeatureContext) -> InventoryHostFeatureAssembly:
	var assembly := InventoryOperationRulesFeatureAssembly.new()
	assembly.policy = build_operation_policy()
	assembly.respect_infinite_supply_tag = respect_infinite_supply_tag
	return assembly
