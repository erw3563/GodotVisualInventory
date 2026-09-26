class_name InventoryOperationFingerprint
extends RefCounted
## 结构事实签名，支持无路径的测试/运行时资源脚本及资源引用环。
static func of(value: Variant) -> int:
	return hash(_describe(value, {}))
static func _describe(value: Variant, visited: Dictionary) -> Variant:
	if value is Script:
		return ["script", value.get_instance_id()]
	if value is Resource:
		if visited.has(value):
			return ["reference", visited[value]]
		visited[value] = visited.size()
		var fields: Array = ["resource", _describe(value.get_script(), visited)]
		for property in value.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE and property.name not in ["script", "resource_path", "resource_scene_unique_id"]:
				fields.append([property.name, _describe(value.get(property.name), visited)])
		if value is ItemInstanceState:
			fields.append(["operation_facts", _describe(value.get_operation_facts(), visited)])
		return fields
	if value is Array:
		var values: Array = []
		for entry in value:
			values.append(_describe(entry, visited))
		return values
	if value is Dictionary:
		var pairs: Array = []
		for key in value:
			pairs.append([_describe(key, visited), _describe(value[key], visited)])
		return pairs
	if value is Object:
		return ["object", value.get_instance_id() if is_instance_valid(value) else 0]
	return value
