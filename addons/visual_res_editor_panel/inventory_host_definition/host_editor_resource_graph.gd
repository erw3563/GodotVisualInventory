@tool
extends RefCounted
## 编辑器隔离资源图：Script/Texture/PackedScene/Shader 是只读叶子，其余资源与容器显式遍历。
static func fields(resource: Resource) -> Array[StringName]:
	var result: Array[StringName] = []
	for info in resource.get_property_list():
		if info.usage & PROPERTY_USAGE_STORAGE and info.name not in ["script", "resource_path"]:
			result.append(info.name)
	return result

static func leaf(value: Variant) -> bool:
	return value is Script or value is Texture2D or value is PackedScene or value is Shader

static func copy(value: Variant, originals: Dictionary = {}, reverse: Dictionary = {}) -> Variant:
	if leaf(value):
		return value
	if value is Resource:
		if originals.has(value):
			return originals[value]
		var result: Resource = value.duplicate(false)
		originals[value] = result
		reverse[result] = value
		for key in fields(value):
			result.set(key, copy(value.get(key), originals, reverse))
		return result
	if value is Array:
		var result: Array = value.duplicate()
		for i in value.size():
			result[i] = copy(value[i], originals, reverse)
		return result
	if value is Dictionary:
		var result: Dictionary = value.duplicate()
		result.clear()
		for key in value:
			result[copy(key, originals, reverse)] = copy(value[key], originals, reverse)
		return result
	return value

static func stamp(value: Variant, identity := false, seen: Dictionary = {}) -> String:
	if leaf(value):
		return "leaf:%s" % value.get_instance_id()
	if value is Resource:
		if seen.has(value):
			return "@%s" % seen[value]
		seen[value] = seen.size()
		var parts: Array[String] = [value.get_class(), str(value.get_script()), str(value.get_instance_id()) if identity else ""]
		for key in fields(value):
			parts.append(str(key) + ":" + stamp(value.get(key), identity, seen))
		return "|".join(parts)
	if value is Array:
		var parts: Array[String] = ["array:%s:%s" % [value.get_typed_builtin(), value.get_typed_script()]]
		for item in value:
			parts.append(stamp(item, identity, seen))
		return "[" + "|".join(parts) + "]"
	if value is Dictionary:
		var parts: Array[String] = []
		for key in value:
			parts.append(stamp(key, identity, seen) + ":" + stamp(value[key], identity, seen))
		return "{" + "|".join(parts) + "}"
	return var_to_str(value)

## 只准备补丁，不修改原件。cache 在整个事务共用，以保留跨资源别名。
static func prepare(value: Variant, reverse: Dictionary, patches: Array, cache: Dictionary) -> Variant:
	if leaf(value):
		return value
	if value is Resource:
		if cache.has(value):
			return cache[value]
		var existing: bool = reverse.has(value)
		var result: Resource = reverse[value] if existing else value.duplicate(false)
		cache[value] = result
		for key in fields(value):
			var next: Variant = prepare(value.get(key), reverse, patches, cache)
			if existing:
				if stamp(next, true) != stamp(result.get(key), true):
					patches.append([result, key, next, result.get(key)])
			else:
				result.set(key, next)
		return result
	if value is Array:
		var result: Array = value.duplicate()
		for i in value.size():
			result[i] = prepare(value[i], reverse, patches, cache)
		return result
	if value is Dictionary:
		var result: Dictionary = value.duplicate()
		result.clear()
		for key in value:
			result[prepare(key, reverse, patches, cache)] = prepare(value[key], reverse, patches, cache)
		return result
	return value
