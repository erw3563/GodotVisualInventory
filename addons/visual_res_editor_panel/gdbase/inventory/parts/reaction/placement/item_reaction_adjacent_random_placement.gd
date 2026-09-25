@tool
class_name ItemReactionAdjacentRandomPlacement
extends ItemReactionPlacementPolicy
## 在源轮廓外的相邻候选锚点随机放置；不合并、不远处寻位。
enum SelectionMode { LEGAL_CELLS, DRAW_ONCE }
@export var offsets: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
@export var selection_mode: SelectionMode = SelectionMode.LEGAL_CELLS
func validate_configuration() -> StringName:
	if selection_mode not in [SelectionMode.LEGAL_CELLS, SelectionMode.DRAW_ONCE]:
		return &"invalid_adjacent_selection_mode"
	return &"invalid_neighbor_offsets" if offsets.is_empty() or offsets.has(Vector2i.ZERO) else &""
func plan_item(context: ItemReactionPlanContext, item: ItemInstanceData) -> ItemReactionPlanResult:
	if not context.view.is_spatial() or not context.view.has_item(context.source):
		return ItemReactionPlanResult.failed(&"adjacent_source_unavailable")
	var cells: Array[Vector2i] = []
	var source_cells := context.view.get_cells(context.source)
	for cell in source_cells:
		for offset in offsets:
			var candidate := cell + offset
			if not source_cells.has(candidate) and not cells.has(candidate):
				cells.append(candidate)
	if cells.is_empty():
		return ItemReactionPlanResult.failed(&"no_adjacent_placement")
	if selection_mode == SelectionMode.DRAW_ONCE:
		var chosen := cells[context.random.randi_range(0, cells.size() - 1)]
		return context.append(InventoryOperationRequest.Type.PLACE_AT, item, -1, chosen)
	var candidates: Array[ItemReactionPlanContext] = []
	for cell in cells:
		var branch := context.fork()
		if branch.append(InventoryOperationRequest.Type.PLACE_AT, item, -1, cell).is_planned():
			candidates.append(branch)
	if candidates.is_empty():
		return ItemReactionPlanResult.failed(&"no_adjacent_placement")
	context.adopt(candidates[context.random.randi_range(0, candidates.size() - 1)])
	return ItemReactionPlanResult.planned()
