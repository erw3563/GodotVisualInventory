class_name InventoryInputConfigurationComposer
extends RefCounted
## 在运行时复制并合并Host 功能输入，不修改共享 Resource。


static func compose_routes(
	feature_assemblies: Array[InventoryHostFeatureAssembly]
) -> Array[InventoryInputActionRoute]:
	var ordered_ids: Array[StringName] = []
	var processors_by_action: Dictionary[StringName, Array] = {}
	for feature_assembly in _ordered(feature_assemblies):
		if feature_assembly != null:
			_append_routes(
				feature_assembly.action_routes,
				ordered_ids,
				processors_by_action
			)
	var result: Array[InventoryInputActionRoute] = []
	for action_id in ordered_ids:
		var processors: Array[InventoryInputActionProcessor] = []
		for processor in processors_by_action[action_id]:
			processors.append(processor)
		result.append(InventoryInputActionRoute.create(action_id, processors))
	return result


static func compose_observers(
	feature_assemblies: Array[InventoryHostFeatureAssembly]
) -> Array[InventoryInputActionObserver]:
	var result: Array[InventoryInputActionObserver] = []
	for feature_assembly in _ordered(feature_assemblies):
		if feature_assembly != null:
			result.append_array(feature_assembly.action_observers)
	return result


static func _append_routes(
	routes: Array[InventoryInputActionRoute],
	ordered_ids: Array[StringName],
	processors_by_action: Dictionary[StringName, Array]
) -> void:
	for route in routes:
		if route == null:
			continue
		if not processors_by_action.has(route.action_id):
			ordered_ids.append(route.action_id)
			processors_by_action[route.action_id] = []
		processors_by_action[route.action_id].append_array(route.processors)


static func _ordered(assemblies: Array[InventoryHostFeatureAssembly]) -> Array[InventoryHostFeatureAssembly]:
	var result: Array[InventoryHostFeatureAssembly] = []
	# Stable insertion: equal priorities retain the Definition list order.
	for assembly in assemblies:
		var index := 0
		while index < result.size() and result[index].input_priority >= assembly.input_priority:
			index += 1
		result.insert(index, assembly)
	return result
