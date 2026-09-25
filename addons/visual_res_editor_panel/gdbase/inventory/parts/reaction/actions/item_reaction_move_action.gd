@tool
class_name ItemReactionMoveAction
extends ItemReactionAction
enum MovementMode { EXACT, UP_TO }
@export var direction_policy: ItemReactionDirectionPolicy
@export_range(1, 128, 1) var distance := 1
@export var movement_mode: MovementMode = MovementMode.EXACT
func validate_configuration() -> StringName:
	if direction_policy == null or distance <= 0 or distance > 128 or movement_mode not in [MovementMode.EXACT, MovementMode.UP_TO]:
		return &"invalid_move_configuration"
	return direction_policy.validate_configuration()
func plan(context: ItemReactionPlanContext) -> ItemReactionPlanResult:
	if not context.view.is_spatial() or not context.view.has_item(context.source):
		return ItemReactionPlanResult.failed(&"movement_source_unavailable")
	for direction in direction_policy.get_directions():
		var world := direction
		if direction_policy.local_space:
			world = ShapeTransform.to_world_direction_with_dir(direction, context.view.get_item(context.source).dir)
		var candidate := context.fork()
		var moved := 0
		for step in distance:
			var trial := candidate.fork()
			var result := trial.append(InventoryOperationRequest.Type.MOVE_WITHIN, context.source, -1, candidate.view.get_cell(context.source) + world)
			if not result.is_planned():
				break
			candidate = trial
			moved += 1
		if moved == distance or (movement_mode == MovementMode.UP_TO and moved > 0):
			context.adopt(candidate)
			return ItemReactionPlanResult.planned()
	return ItemReactionPlanResult.failed(&"movement_path_blocked")
