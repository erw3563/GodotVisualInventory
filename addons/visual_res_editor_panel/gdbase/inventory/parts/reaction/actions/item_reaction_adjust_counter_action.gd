@tool
class_name ItemReactionAdjustCounterAction
extends ItemReactionAction
enum TargetMode { SELF, SELECTED }
@export var target_mode: TargetMode = TargetMode.SELF
@export var selector: ItemReactionTargetSelector
@export var counter_key: String = ""
@export var delta: int = -1

func validate_configuration() -> StringName:
	if counter_key.is_empty():
		return &"invalid_counter_key"
	if delta == 0:
		return &"counter_delta_zero"
	if target_mode == TargetMode.SELF:
		return &""
	if target_mode != TargetMode.SELECTED:
		return &"invalid_counter_target_mode"
	return selector.validate_configuration() if selector != null else &"missing_counter_selector"

func plan(context: ItemReactionPlanContext) -> ItemReactionPlanResult:
	var reason := validate_configuration()
	if reason != &"":
		return ItemReactionPlanResult.failed(reason, true)
	var targets: Array[ItemInstanceData] = []
	if target_mode == TargetMode.SELF:
		targets.append(context.source)
	else:
		var queried := selector.query(context)
		if queried.error_code != &"":
			return ItemReactionPlanResult.failed(queried.error_code)
		targets = queried.items
	if targets.is_empty():
		return ItemReactionPlanResult.failed(&"counter_targets_empty")
	for target in targets:
		if target == context.protected_counter_item and counter_key == context.protected_counter_key:
			return ItemReactionPlanResult.failed(&"trigger_counter_write_forbidden")
		var change := InventoryCounterOperations.plan_change(context.view, target, counter_key, delta)
		if change.reason_key != &"":
			return ItemReactionPlanResult.failed(change.reason_key)
		if change.state != null:
			var result := context.append(InventoryOperationRequest.Type.UPDATE_STATES, target, -1, Vector2i(-1, -1), null, change.states)
			if not result.is_planned():
				return result
	return ItemReactionPlanResult.planned()
