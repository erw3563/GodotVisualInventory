@abstract
class_name InventoryTargetRule
extends Resource
## 校验查询、规范化候选与区域，再按共享过滤配置返回独立结果。

@export var filters: Array[InventoryTargetFilter] = []
@export var exclude_source := true

func validate_configuration() -> StringName:
	for filter in filters:
		if filter == null:
			return &"invalid_rule_configuration"
		var error := filter.validate_configuration()
		if error != &"":
			return error
	return &""

func validate_context(context: InventoryTargetQueryContext) -> StringName:
	if context == null:
		return &"invalid_context"
	var error := context.validate()
	if error != &"":
		return error
	for filter in filters:
		if filter == null:
			return &"invalid_rule_configuration"
		error = filter.validate_context(context)
		if error != &"":
			return error
	return &""

func query(context: InventoryTargetQueryContext) -> InventoryTargetQueryResult:
	var error := validate_configuration()
	if error == &"":
		error = validate_context(context)
	if error != &"":
		return InventoryTargetQueryResult.failure(error)
	var candidates := _query_candidates(context)
	if candidates == null:
		return InventoryTargetQueryResult.failure(&"invalid_target_result")
	if candidates.error_code != &"":
		return InventoryTargetQueryResult.failure(candidates.error_code)
	var result := InventoryTargetQueryResult.new()
	result.has_zone = candidates.has_zone
	for item in candidates.items:
		if not context.has_item(item):
			return InventoryTargetQueryResult.failure(&"invalid_target_result")
		if not result.items.has(item):
			result.items.append(item)
	for cell in candidates.zone_cells:
		if not candidates.has_zone or not context.is_spatial() or not context.has_region_cell(cell):
			return InventoryTargetQueryResult.failure(&"invalid_target_result")
		if not result.zone_cells.has(cell):
			result.zone_cells.append(cell)
	var filtered: Array[ItemInstanceData] = []
	for item in result.items:
		if exclude_source and item == context.source:
			continue
		var accepted := true
		for filter in filters:
			if not filter.matches(item, context):
				accepted = false
				break
		if accepted:
			filtered.append(item)
	result.items = filtered
	return result

@abstract func _query_candidates(context: InventoryTargetQueryContext) -> InventoryTargetQueryResult
