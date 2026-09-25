@tool
class_name ShopRotateFeatureDefinition
extends ShopInputFeatureDefinition

func create_assembly(_context: InventoryHostFeatureContext) -> InventoryHostFeatureAssembly:
	var assembly := ShopInputFeatureAssembly.new()
	assembly.processor = ShopRotateInputActionProcessor.new()
	for action in [InventoryInputActionIds.ROTATE]:
		assembly.action_routes.append(InventoryInputActionRoute.create(action, [assembly.processor]))
	return assembly

func get_exclusive_roles() -> Array[StringName]:
	return [InventoryHostFeatureRoles.ROTATE]
