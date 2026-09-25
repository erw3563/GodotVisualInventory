@tool
class_name NestedInventoryCyclePreventionFeatureDefinition
extends InventoryHostFeatureDefinition
## 嵌套库存防环：为目标端点贡献 ContainmentCycleRule；未安装时允许成环。


func build_operation_policy() -> InventoryOperationPolicy:
	var policy := InventoryOperationPolicy.new()
	policy.rules.append(InventoryContainmentCycleRule.new())
	return policy


func create_assembly(_context: InventoryHostFeatureContext) -> InventoryHostFeatureAssembly:
	var assembly := NestedInventoryCyclePreventionFeatureAssembly.new()
	assembly.policy = build_operation_policy()
	return assembly
