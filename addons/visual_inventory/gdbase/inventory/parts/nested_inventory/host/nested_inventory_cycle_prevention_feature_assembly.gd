class_name NestedInventoryCyclePreventionFeatureAssembly
extends InventoryHostFeatureAssembly
## 嵌套库存防环运行时装配：向端点贡献防环 Rule。

var policy: InventoryOperationPolicy


func get_operation_policy() -> InventoryOperationPolicy:
	return policy
