class_name InventoryHostAssembly
extends RefCounted
## 单个 InventoryHost 的总运行时装配结果。

var operation_endpoint: InventoryOperationEndpoint
var panel_assembly: InventoryPanelAssembly
var features_by_type: Dictionary = {}
var feature_assemblies: Array[InventoryHostFeatureAssembly] = []
var action_routes: Array[InventoryInputActionRoute] = []
var action_observers: Array[InventoryInputActionObserver] = []


func teardown(panel_definition: InventoryPanelAssemblyDefinition) -> void:
	if operation_endpoint != null:
		operation_endpoint.invalidate()
	for index in range(feature_assemblies.size() - 1, -1, -1):
		var feature_assembly := feature_assemblies[index]
		if feature_assembly != null:
			feature_assembly.teardown()
	feature_assemblies.clear()
	features_by_type.clear()
	action_routes.clear()
	action_observers.clear()
	if panel_assembly != null:
		if panel_definition != null:
			panel_definition.teardown_assembly(panel_assembly)
		else:
			panel_assembly.teardown()
	panel_assembly = null
