@tool
class_name InventoryHostFeatureValidator
extends RefCounted
## 对完整功能列表执行结构、身份及业务配置校验。
static func diagnose(features: Array[InventoryHostFeatureDefinition], configuration := true) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var types: Dictionary = {}
	var roles_by_index: Array[Array] = []
	for index in features.size():
		var feature := features[index]
		roles_by_index.append([])
		if feature == null:
			result.append({"index": index, "reason": &"inventory_feature_missing"})
			continue
		if types.has(feature.get_script()):
			result.append({"index": index, "reason": &"inventory_feature_duplicate"})
		types[feature.get_script()] = true
		for role in feature.get_exclusive_roles():
			if role == &"" or role in roles_by_index[index]:
				result.append({"index": index, "reason": &"inventory_feature_role_declaration_invalid"})
			else:
				roles_by_index[index].append(role)
	for index in features.size():
		for other_index in range(index + 1, features.size()):
			var shared: Array[StringName] = []
			for role in roles_by_index[index]:
				if role in roles_by_index[other_index]:
					shared.append(role)
			if shared.is_empty():
				continue
			shared.sort()
			result.append({"index": index, "other_index": other_index,
				"type": features[index].get_script(), "other_type": features[other_index].get_script(),
				"roles": shared, "reason": &"inventory_feature_role_conflict"})
	if configuration:
		for index in features.size():
			if features[index] == null:
				continue
			var reason := features[index].validate_configuration(features)
			if reason != &"":
				result.append({"index": index, "reason": reason})
	return result
