@tool
class_name InventoryPlaceFeatureDefinition
extends InventoryHostFeatureDefinition
## 基础放置；每 Host 独立处理器同时服务整组与单件路由。

func create_assembly(_context: InventoryHostFeatureContext) -> InventoryHostFeatureAssembly:
	var assembly := InventoryHostFeatureAssembly.new()
	var processor := StandardPlaceInputActionProcessor.new()
	assembly.action_routes = [
		InventoryInputActionRoute.create(InventoryInputActionIds.PRIMARY, [processor]),
		InventoryInputActionRoute.create(InventoryInputActionIds.PRIMARY_SINGLE, [processor])
	]
	return assembly

func get_exclusive_roles() -> Array[StringName]:
	return [InventoryHostFeatureRoles.PLACE]
