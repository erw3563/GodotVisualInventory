@tool
class_name ItemReactionTargetSelector
extends Resource
## 查询本次预计事实，并按库存成员顺序提供反应目标。

@export var target_rule: InventoryTargetRule

func validate_configuration() -> StringName:
	return target_rule.validate_configuration() if target_rule != null else &"invalid_rule_configuration"

func query(context: ItemReactionPlanContext) -> InventoryTargetQueryResult:
	var error := validate_configuration()
	if error != &"":
		return InventoryTargetQueryResult.failure(error)
	if context == null:
		return InventoryTargetQueryResult.failure(&"invalid_context")
	var view := context.view
	var result := target_rule.query(InventoryTargetQueryContext.projected(view, context.source))
	if result.error_code != &"":
		return result
	var selected: Dictionary = {}
	for item in result.items:
		selected[item] = true
	var ordered: Array[ItemInstanceData] = []
	for item in view.get_items():
		if selected.has(item):
			ordered.append(item)
	result.items = ordered
	return result
