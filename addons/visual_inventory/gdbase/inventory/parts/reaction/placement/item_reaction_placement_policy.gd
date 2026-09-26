@tool
@abstract
class_name ItemReactionPlacementPolicy
extends Resource
func validate_configuration() -> StringName:
	return &""
@abstract func plan_item(context: ItemReactionPlanContext, item: ItemInstanceData) -> ItemReactionPlanResult
