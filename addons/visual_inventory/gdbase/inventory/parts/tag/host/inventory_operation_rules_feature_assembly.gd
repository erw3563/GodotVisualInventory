class_name InventoryOperationRulesFeatureAssembly
extends InventoryHostFeatureAssembly

var policy: InventoryOperationPolicy
var respect_infinite_supply_tag := true

func get_operation_policy() -> InventoryOperationPolicy:
	return policy
