class_name ItemResourceGraph
extends RefCounted
## 复制已验证的资源图，隔离实例事实并按 State 协议保留只读模板引用；图内回边按身份映射保留。

static func copy(source: Resource) -> Resource:
	if source == null:
		return null
	var shared: Dictionary = {}
	_collect_shared(source, {}, shared)
	var candidate := source.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	return _restore_shared(source, candidate, shared, {}) as Resource

static func _collect_shared(value: Variant, seen: Dictionary, shared: Dictionary) -> void:
	if value is ItemData or value is Script:
		shared[value] = true
		return
	if value is Resource:
		if seen.has(value):
			return
		seen[value] = true
		if value is ItemInstanceData:
			if value.item_data != null:
				shared[value.item_data] = true
			for state in value.instance_states:
				if state != null:
					for definition in state.get_shared_template_resources(value.item_data):
						if definition != null:
							shared[definition] = true
		for property in value.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE:
				_collect_shared(value.get(property.name), seen, shared)
	elif value is Array:
		for entry in value:
			_collect_shared(entry, seen, shared)
	elif value is Dictionary:
		for key in value:
			_collect_shared(key, seen, shared)
			_collect_shared(value[key], seen, shared)

static func _restore_shared(source: Variant, candidate: Variant, shared: Dictionary, seen: Dictionary) -> Variant:
	if source is Resource:
		if shared.has(source):
			return source
		if is_same(source, candidate):
			return candidate
		if seen.has(source):
			return seen[source]
		seen[source] = candidate
		if source is ItemInstanceData:
			var states: Array[ItemInstanceState] = candidate.instance_states.duplicate()
			candidate.item_data = source.item_data
			candidate.instance_states = states
		for property in source.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE:
				var original: Variant = source.get(property.name)
				var copied: Variant = candidate.get(property.name)
				var restored: Variant = _restore_shared(original, copied, shared, seen)
				if not is_same(copied, restored):
					candidate.set(property.name, restored)
	elif source is Array:
		for index in source.size():
			candidate[index] = _restore_shared(source[index], candidate[index], shared, seen)
	elif source is Dictionary:
		var source_keys: Array = source.keys()
		var candidate_keys: Array = candidate.keys()
		var entries: Array = []
		for index in source_keys.size():
			var key: Variant = source_keys[index]
			var copied_key: Variant = candidate_keys[index]
			entries.append([_restore_shared(key, copied_key, shared, seen), _restore_shared(source[key], candidate[copied_key], shared, seen)])
		candidate.clear()
		for entry in entries:
			candidate[entry[0]] = entry[1]
	return candidate
