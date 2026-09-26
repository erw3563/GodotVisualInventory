@tool
class_name ItemReactionSequenceAction
extends ItemReactionAction
@export var actions: Array[ItemReactionAction] = []
func validate_configuration() -> StringName:
	return &"empty_reaction_sequence" if actions.is_empty() else &""
func get_child_actions() -> Array[ItemReactionAction]:
	return actions.duplicate()
func plan(context: ItemReactionPlanContext) -> ItemReactionPlanResult:
	for index in actions.size():
		var result := actions[index].plan(context)
		if result == null:
			return ItemReactionPlanResult.failed(&"invalid_reaction_result", true)
		if not result.is_planned():
			result.step_path.push_front(index)
			return result
	return ItemReactionPlanResult.planned()
