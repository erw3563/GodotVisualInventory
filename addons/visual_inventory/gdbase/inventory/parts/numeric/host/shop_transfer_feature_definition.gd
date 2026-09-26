@tool
class_name ShopTransferFeatureDefinition
extends ShopInputFeatureDefinition
## 为本 Host 提供消费转移审查、结算贡献与快捷输入。
func create_assembly(_context: InventoryHostFeatureContext) -> InventoryHostFeatureAssembly:
	var assembly := ShopTransferFeatureAssembly.new()
	var processor := StandardQuickTransferInputActionProcessor.new()
	for action in [InventoryInputActionIds.QUICK_TRANSFER, InventoryInputActionIds.QUICK_TRANSFER_SINGLE]:
		assembly.action_routes.append(InventoryInputActionRoute.create(action, [processor]))
	return assembly

func get_exclusive_roles() -> Array[StringName]:
	return [InventoryHostFeatureRoles.TRANSFER]
