@tool
class_name ItemReactionPushAction
extends ItemReactionAction
## 源前方接触链整体移动一格；每个目标只规划一次。
@export var target_direction: Vector2i = Vector2i.RIGHT
static func is_valid_target_direction(direction: Vector2i) -> bool:
	return abs(direction.x) + abs(direction.y) == 1
func validate_configuration() -> StringName:
	return &"" if is_valid_target_direction(target_direction) else &"invalid_push_direction"
func plan(context: ItemReactionPlanContext) -> ItemReactionPlanResult:
	if not context.view.is_spatial() or not context.view.has_item(context.source):
		return ItemReactionPlanResult.failed(&"push_source_unavailable")
	var world := ShapeTransform.to_world_direction_with_dir(target_direction, context.view.get_item(context.source).dir)
	var targets := _front(context.view, context.source, world)
	if targets.is_empty():
		return ItemReactionPlanResult.failed(&"push_target_missing")
	var order: Array[ItemInstanceData] = []
	var visited: Dictionary = {}
	for target in targets:
		if not _collect_chain(context.view, target, context.source, world, visited, order):
			return ItemReactionPlanResult.failed(&"push_chain_blocked")
	for target in order:
		var result := context.append(InventoryOperationRequest.Type.MOVE_WITHIN, target, -1, context.view.get_cell(target) + world)
		if not result.is_planned():
			return result
	return ItemReactionPlanResult.planned()
func _front(view: InventoryOperationView, source: ItemInstanceData, direction: Vector2i) -> Array[ItemInstanceData]:
	var result: Array[ItemInstanceData] = []
	var cells := view.get_cells(source)
	for cell in cells:
		if cells.has(cell + direction):
			continue
		var item := view.get_item_at(cell + direction)
		if item != null and not result.has(item):
			result.append(item)
	return result
func _collect_chain(view: InventoryOperationView, item: ItemInstanceData, source: ItemInstanceData, direction: Vector2i, visited: Dictionary, order: Array[ItemInstanceData]) -> bool:
	if item == source:
		return false
	if visited.has(item):
		return visited[item] == 2
	visited[item] = 1
	for cell in view.get_cells(item):
		if not view.get_region().has(cell + direction):
			return false
	for blocker in _front(view, item, direction):
		if not _collect_chain(view, blocker, source, direction, visited, order):
			return false
	visited[item] = 2
	order.append(item)
	return true
