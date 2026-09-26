@tool
class_name ItemReactionAddAction
extends ItemReactionAction
@export var output_source: ItemReactionOutputSource
@export var placement_policy: ItemReactionPlacementPolicy
func validate_configuration() -> StringName:
	if output_source == null or placement_policy == null:
		return &"invalid_add_configuration"
	var reason := output_source.validate_configuration()
	return reason if reason != &"" else placement_policy.validate_configuration()
func plan(context: ItemReactionPlanContext) -> ItemReactionPlanResult:
	var output := output_source.sample(context)
	if output.is_empty():
		return ItemReactionPlanResult.failed(&"empty_output")
	for entry in output:
		var remaining := entry.quantity
		if entry.item_data.max_num <= 0:
			return ItemReactionPlanResult.failed(&"invalid_item_maximum", true)
		while remaining > 0:
			var amount := mini(remaining, entry.item_data.max_num)
			var item := ItemInstanceData.new()
			item.init(entry.item_data, amount)
			var result := placement_policy.plan_item(context, item)
			if not result.is_planned():
				return result
			remaining -= amount
	return ItemReactionPlanResult.planned()
