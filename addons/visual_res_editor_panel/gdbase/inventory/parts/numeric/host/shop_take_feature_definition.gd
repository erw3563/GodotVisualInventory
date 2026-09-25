@tool
class_name ShopTakeFeatureDefinition
extends ShopInputFeatureDefinition

func create_assembly(_context: InventoryHostFeatureContext) -> InventoryHostFeatureAssembly:
	var assembly := ShopInputFeatureAssembly.new()
	assembly.processor = ShopTakeInputActionProcessor.new()
	for action in [InventoryInputActionIds.PRIMARY, InventoryInputActionIds.PRIMARY_SINGLE]:
		assembly.action_routes.append(InventoryInputActionRoute.create(action, [assembly.processor]))
	return assembly

func get_exclusive_roles() -> Array[StringName]:
	return [InventoryHostFeatureRoles.TAKE]
