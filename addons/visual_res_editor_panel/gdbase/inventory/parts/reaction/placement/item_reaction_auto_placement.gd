@tool
class_name ItemReactionAutoPlacement
extends ItemReactionPlacementPolicy
@export var allow_merge := true
func plan_item(context: ItemReactionPlanContext, item: ItemInstanceData) -> ItemReactionPlanResult:
	return context.append(InventoryOperationRequest.Type.ADD_WITH_MERGE if allow_merge else InventoryOperationRequest.Type.ADD_WITHOUT_MERGE, item)
