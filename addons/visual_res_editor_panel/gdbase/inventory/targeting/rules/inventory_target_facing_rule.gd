class_name InventoryTargetFacingRule
extends InventoryTargetRule
## 逐源格沿朝向扫描连续物品，过滤在射线扫描完成后执行。

@export var local_direction: Vector2i = Vector2i.RIGHT
@export var only_first := false

func validate_configuration() -> StringName:
	if absi(local_direction.x) + absi(local_direction.y) != 1:
		return &"invalid_rule_configuration"
	return super.validate_configuration()

func validate_context(context: InventoryTargetQueryContext) -> StringName:
	var error := super.validate_context(context)
	if error != &"":
		return error
	error = context.validate_spatial()
	if error != &"":
		return error
	var direction := context.get_source_direction()
	if direction not in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
		return &"invalid_context"
	return &""

func _query_candidates(context: InventoryTargetQueryContext) -> InventoryTargetQueryResult:
	var result := InventoryTargetQueryResult.new()
	var source_cells := context.get_source_cells()
	var direction := ShapeTransform.to_world_direction_with_dir(local_direction, context.get_source_direction())
	for source_cell in source_cells:
		var cell := source_cell + direction
		while context.has_region_cell(cell):
			var item := context.get_item_at(cell)
			if source_cells.has(cell) or item == context.source:
				cell += direction
				continue
			if item == null:
				break
			result.items.append(item)
			if only_first:
				break
			cell += direction
	return result
