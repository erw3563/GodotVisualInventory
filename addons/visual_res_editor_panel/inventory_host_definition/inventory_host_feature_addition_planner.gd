@tool
extends RefCounted
## 准备功能依赖与身份替换候选，保留原草稿资源。
var _catalog: RefCounted
var _layout: Resource
var _entries: Array[Dictionary] = []
var _features: Array[InventoryHostFeatureDefinition] = []
var _created: Array[InventoryHostFeatureDefinition] = []
var _visited: Dictionary = {}
var _chains: Dictionary = {}
var _result: Dictionary = {}

func prepare(catalog: RefCounted, entries: Array[Dictionary], requested_type: Script, selected: int, layout: Resource = null) -> Dictionary:
	_catalog = catalog
	_layout = layout
	_result = {"ok": false, "requested_type": requested_type, "added_types": [], "dependency_types": [],
		"removed_types": [], "removed_roles": [], "selected_index": selected, "error_code": &"", "dependency_chain": [], "conflicts": [], "detail": ""}
	for entry in entries:
		_features.append(entry.draft)
	var original := _features.duplicate()
	var baseline := _issues(_features)
	if not catalog.errors.is_empty():
		return _fail(&"catalog_invalid", [requested_type], "\n".join(catalog.errors))
	if catalog.find(requested_type).is_empty():
		return _fail(&"feature_unavailable", [requested_type])
	for feature in _features:
		if feature != null and feature.get_script() == requested_type:
			return _fail(&"feature_duplicate", [requested_type])
	var requested := _visit(requested_type, [], false)
	if requested == null:
		return _result
	var removed: Array[InventoryHostFeatureDefinition] = []
	for issue in InventoryHostFeatureValidator.diagnose(_features, false):
		var first := _features[issue.index]
		if issue.reason != &"inventory_feature_role_conflict":
			if first in _created:
				return _fail(&"declaration_invalid", _chains.get(first, [requested_type]), str(issue.reason))
			continue
		var second := _features[issue.other_index]
		if first not in _created and second not in _created:
			continue
		_result.conflicts.append(issue)
		if first in _created and second in _created:
			return _fail(&"feature_conflict", [requested_type])
		var existing := second if first in _created else first
		if existing not in removed:
			removed.append(existing)
	var insertion := -1
	for entry in entries:
		if entry.draft in removed:
			if insertion < 0:
				insertion = _entries.size()
			continue
		_entries.append(entry)
	if insertion < 0:
		insertion = _entries.size()
	for feature in _created:
		_entries.insert(insertion, {"draft": feature, "reference": null, "editable": true})
		insertion += 1
	_features.clear()
	for entry in _entries:
		_features.append(entry.draft)
	for feature in _features:
		if feature == null:
			continue
		for requirement in _catalog.requirements(feature.get_script()):
			if _find_feature(requirement.type) == null:
				var lost := false
				for old in removed:
					if is_instance_of(old, requirement.type):
						lost = true
				if feature in _created or lost:
					return _fail(&"replacement_dependency_missing", [feature.get_script(), requirement.type])
	var order := _sort()
	if not _result.error_code.is_empty():
		return _result
	var ordered: Array[InventoryHostFeatureDefinition] = []
	var ordered_entries: Array[Dictionary] = []
	for index in order:
		ordered.append(_features[index])
		ordered_entries.append(_entries[index])
	var candidate_issues := _issues(ordered)
	for key in candidate_issues:
		if key not in baseline:
			return _fail(&"configuration_invalid", [requested_type], candidate_issues[key])
	_result.ok = true
	_result.selected_index = ordered.find(requested)
	_result["entries"] = ordered_entries
	for feature in ordered:
		if feature in _created:
			_result.added_types.append(feature.get_script())
			if feature != requested:
				_result.dependency_types.append(feature.get_script())
	for feature in original:
		if feature in removed:
			_result.removed_types.append(feature.get_script())
			_result.removed_roles.append(feature.get_exclusive_roles())
	return _result

func _issues(features: Array[InventoryHostFeatureDefinition]) -> Dictionary:
	var result: Dictionary = {}
	for issue in _catalog.diagnose(_layout, features):
		if not issue.has("error"):
			continue
		var feature := features[issue.index]
		var other: InventoryHostFeatureDefinition = features[issue.other_index] if issue.has("other_index") else null
		var key := "%s:%s:%s" % [feature.get_instance_id() if feature != null else 0, other.get_instance_id() if other != null else 0, issue.get("reason", issue.error)]
		result[key] = issue.error
	return result

func _visit(type: Script, parents: Array, match_existing := true) -> InventoryHostFeatureDefinition:
	var chain := parents.duplicate()
	chain.append(type)
	if type in parents:
		_fail(&"dependency_cycle", chain)
		return null
	var feature: InventoryHostFeatureDefinition = _find_feature(type) if match_existing else null
	var fresh := feature == null
	if fresh:
		if _catalog.find(type).is_empty():
			_fail(&"dependency_unavailable", chain)
			return null
		feature = type.new()
		_features.append(feature)
	if _visited.get(feature, 0) == 1:
		_fail(&"dependency_cycle", chain)
		return null
	if _visited.get(feature, 0) == 2:
		return feature
	_visited[feature] = 1
	_chains[feature] = chain
	var info: Dictionary = _catalog.find(feature.get_script())
	var declaration_error: String = _catalog.validate_addition_metadata(info)
	if not declaration_error.is_empty():
		_fail(&"declaration_invalid", chain, declaration_error)
		return null
	for requirement in info.get("required_features", []):
		if _visit(requirement.type, chain) == null:
			return null
	_visited[feature] = 2
	if fresh:
		_created.append(feature)
	return feature

func _find_feature(type: Script) -> InventoryHostFeatureDefinition:
	for feature in _features:
		if feature != null and is_instance_of(feature, type):
			return feature
	return null

func _sort() -> Array[int]:
	var edges: Array[Array] = []
	var incoming: Array[int] = []
	for index in _entries.size():
		edges.append([])
		incoming.append(0)
	var previous := -1
	for index in _features.size():
		if _features[index] not in _created:
			if previous >= 0:
				_link(edges, incoming, previous, index)
			previous = index
	for index in _features.size():
		var feature := _features[index]
		if feature == null:
			continue
		for requirement in _catalog.requirements(feature.get_script()):
			if not requirement.before:
				continue
			var provider := _find_feature(requirement.type)
			if provider != null and (_visited.has(feature) or _visited.has(provider)):
				_link(edges, incoming, _features.find(provider), index)
	var order: Array[int] = []
	while order.size() < _features.size():
		var ready := -1
		for index in incoming.size():
			if incoming[index] == 0:
				ready = index
				break
		if ready < 0:
			var chain: Array = []
			for index in incoming.size():
				if incoming[index] > 0 and _features[index] != null:
					chain.append(_features[index].get_script())
			_fail(&"dependency_order_conflict", chain)
			return []
		order.append(ready)
		incoming[ready] = -1
		for target in edges[ready]:
			incoming[target] -= 1
	return order

func _link(edges: Array[Array], incoming: Array[int], source: int, target: int) -> void:
	if target not in edges[source]:
		edges[source].append(target)
		incoming[target] += 1

func _fail(code: StringName, chain: Array, detail := "") -> Dictionary:
	_result.error_code = code
	_result.dependency_chain = chain
	_result.detail = detail
	return _result
