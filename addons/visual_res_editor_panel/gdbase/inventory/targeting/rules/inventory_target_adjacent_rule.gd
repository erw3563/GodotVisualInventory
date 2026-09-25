class_name InventoryTargetAdjacentRule
extends InventoryTargetRule
## 按源占格与偏移顺序查询邻接区域及其中的物品。

@export var offsets: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]

func validate_configuration() -> StringName:
	if offsets.is_empty() or offsets.has(Vector2i.ZERO):
		return &"invalid_neighbor_offsets"
	return super.validate_configuration()

func validate_context(context: InventoryTargetQueryContext) -> StringName:
	var error := super.validate_context(context)
	return error if error != &"" else context.validate_spatial()

func _query_candidates(context: InventoryTargetQueryContext) -> InventoryTargetQueryResult:
	var result := InventoryTargetQueryResult.new()
	result.has_zone = true
	var source_cells := context.get_source_cells()
	for source_cell in source_cells:
		for offset in offsets:
			var cell := source_cell + offset
			if source_cells.has(cell) or result.zone_cells.has(cell) or not context.has_region_cell(cell):
				continue
			result.zone_cells.append(cell)
			var item := context.get_item_at(cell)
			if item != null and item != context.source:
				result.items.append(item)
	return result
