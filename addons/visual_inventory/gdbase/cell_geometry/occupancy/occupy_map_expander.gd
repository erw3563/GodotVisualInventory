class_name OccupyMapExpander
extends RefCounted
## OccupyMapExpander 负责 OccupyMap 的自动扩容计算。

## 尝试将合法区域扩到可以包含目标格子。
static func try_expand_for_cells(occupy_map: OccupyMap, target_cells: Array[Vector2i]) -> bool:
	if !occupy_map.is_auto_expand:
		return false
	if target_cells.is_empty():
		return true
	var target_bounds := _get_cells_bounds(target_cells)
	while !occupy_map._contains_all_cells(target_cells):
		if !occupy_map._expand_one_step(target_bounds["min_x"], target_bounds["max_x"], target_bounds["min_y"], target_bounds["max_y"]):
			return false
		if _has_reached_target_bounds(occupy_map, target_bounds):
			break
	return occupy_map._contains_all_cells(target_cells)


## 扩容一条带，可沿 X 或 Y 正方向扩展，并覆盖目标范围。
## 会先尝试填补当前边界框内的缺失格子，再向外扩展。
static func expand_one_step(occupy_map: OccupyMap, target_min_x: int = 0, target_max_x: int = 0, target_min_y: int = 0, target_max_y: int = 0) -> bool:
	if !occupy_map.is_auto_expand:
		return false
	var region_bounds := occupy_map.get_region_bounds()
	var target_bounds := {
		"min_x": mini(region_bounds["min_x"], target_min_x),
		"max_x": maxi(region_bounds["max_x"], target_max_x),
		"min_y": mini(region_bounds["min_y"], target_min_y),
		"max_y": maxi(region_bounds["max_y"], target_max_y),
	}
	var internal_missing_cells := _collect_internal_missing_cells(occupy_map, region_bounds)
	if !internal_missing_cells.is_empty():
		return _fill_internal_gaps(
			occupy_map,
			internal_missing_cells,
			target_bounds,
			maxi(1, occupy_map.expand_step)
		)
	if _is_expand_limit_reached(occupy_map, region_bounds):
		return false
	var effective_expand_step := maxi(1, occupy_map.expand_step)
	match occupy_map.expand_direction:
		OccupyMap.ExpandDirection.X_POSITIVE:
			return _expand_x_positive(occupy_map, region_bounds, target_bounds, effective_expand_step)
		OccupyMap.ExpandDirection.Y_POSITIVE:
			return _expand_y_positive(occupy_map, region_bounds, target_bounds, effective_expand_step)
	return false


## 获取下一次扩容时用于放置形状的基准格子。
static func get_expand_base_cell(occupy_map: OccupyMap) -> Vector2i:
	if occupy_map.cells.is_empty():
		return Vector2i.ZERO
	var region_bounds := occupy_map.get_region_bounds()
	var internal_missing_cells := _collect_internal_missing_cells(occupy_map, region_bounds)
	if !internal_missing_cells.is_empty():
		return _pick_first_internal_gap_cell(internal_missing_cells, region_bounds)
	match occupy_map.expand_direction:
		OccupyMap.ExpandDirection.X_POSITIVE:
			return Vector2i(region_bounds["max_x"] + 1, region_bounds["min_y"])
		OccupyMap.ExpandDirection.Y_POSITIVE:
			return Vector2i(region_bounds["min_x"], region_bounds["max_y"] + 1)
		_:
			return Vector2i(region_bounds["max_x"] + 1, region_bounds["min_y"])


## 获取一组目标格子的边界。
static func _get_cells_bounds(input_cells: Array[Vector2i]) -> Dictionary:
	var min_x: int = input_cells[0].x
	var max_x: int = input_cells[0].x
	var min_y: int = input_cells[0].y
	var max_y: int = input_cells[0].y
	for cell in input_cells:
		min_x = mini(min_x, cell.x)
		max_x = maxi(max_x, cell.x)
		min_y = mini(min_y, cell.y)
		max_y = maxi(max_y, cell.y)
	return {
		"min_x": min_x,
		"max_x": max_x,
		"min_y": min_y,
		"max_y": max_y,
	}


## 判断当前区域是否已经沿扩容方向到达目标边界。
static func _has_reached_target_bounds(occupy_map: OccupyMap, target_bounds: Dictionary) -> bool:
	var region_bounds := occupy_map.get_region_bounds()
	match occupy_map.expand_direction:
		OccupyMap.ExpandDirection.X_POSITIVE:
			return region_bounds["max_x"] >= target_bounds["max_x"]
		OccupyMap.ExpandDirection.Y_POSITIVE:
			return region_bounds["max_y"] >= target_bounds["max_y"]
	return false


## 判断当前扩容方向是否已经到达上限。
static func _is_expand_limit_reached(occupy_map: OccupyMap, region_bounds: Dictionary) -> bool:
	var current_width: int = region_bounds["max_x"] - region_bounds["min_x"] + 1
	var current_height: int = region_bounds["max_y"] - region_bounds["min_y"] + 1
	if occupy_map.expand_direction == OccupyMap.ExpandDirection.X_POSITIVE:
		return occupy_map.max_expand_width > 0 and current_width >= occupy_map.max_expand_width
	if occupy_map.expand_direction == OccupyMap.ExpandDirection.Y_POSITIVE:
		return occupy_map.max_expand_height > 0 and current_height >= occupy_map.max_expand_height
	return true


## 沿 X 正方向扩容一组列。
static func _expand_x_positive(occupy_map: OccupyMap, region_bounds: Dictionary, target_bounds: Dictionary, effective_expand_step: int) -> bool:
	var append_cells: Array[Vector2i] = []
	for add_x in effective_expand_step:
		var next_x: int = region_bounds["max_x"] + 1 + add_x
		if occupy_map.max_expand_width > 0:
			var next_width: int = next_x - region_bounds["min_x"] + 1
			if next_width > occupy_map.max_expand_width:
				return occupy_map.cells.size() > 0
		for target_y in range(target_bounds["min_y"], target_bounds["max_y"] + 1):
			append_cells.append(Vector2i(next_x, target_y))
	occupy_map.append_region_cells(append_cells)
	var expanded_bounds := occupy_map.get_region_bounds()
	append_cells.clear()
	_collect_cells_to_y_range(append_cells, region_bounds["min_x"], expanded_bounds["max_x"], target_bounds["min_y"], target_bounds["max_y"])
	occupy_map.append_region_cells(append_cells)
	return true


## 沿 Y 正方向扩容一组行。
static func _expand_y_positive(occupy_map: OccupyMap, region_bounds: Dictionary, target_bounds: Dictionary, effective_expand_step: int) -> bool:
	var append_cells: Array[Vector2i] = []
	for add_y in effective_expand_step:
		var next_y: int = region_bounds["max_y"] + 1 + add_y
		if occupy_map.max_expand_height > 0:
			var next_height: int = next_y - region_bounds["min_y"] + 1
			if next_height > occupy_map.max_expand_height:
				return occupy_map.cells.size() > 0
		for target_x in range(target_bounds["min_x"], target_bounds["max_x"] + 1):
			append_cells.append(Vector2i(target_x, next_y))
	occupy_map.append_region_cells(append_cells)
	var expanded_bounds := occupy_map.get_region_bounds()
	append_cells.clear()
	_collect_cells_to_x_range(append_cells, target_bounds["min_x"], target_bounds["max_x"], region_bounds["min_y"], expanded_bounds["max_y"])
	occupy_map.append_region_cells(append_cells)
	return true


## 收集 X 正方向扩容时旧列缺失的目标高度格子。
static func _collect_cells_to_y_range(append_cells: Array[Vector2i], min_x: int, max_x: int, min_y: int, max_y: int) -> void:
	for target_x in range(min_x, max_x + 1):
		for target_y in range(min_y, max_y + 1):
			append_cells.append(Vector2i(target_x, target_y))


## 收集 Y 正方向扩容时旧行缺失的目标宽度格子。
static func _collect_cells_to_x_range(append_cells: Array[Vector2i], min_x: int, max_x: int, min_y: int, max_y: int) -> void:
	for target_y in range(min_y, max_y + 1):
		for target_x in range(min_x, max_x + 1):
			append_cells.append(Vector2i(target_x, target_y))


## 收集当前边界框内尚未加入合法区域的缺失格子。
static func _collect_internal_missing_cells(occupy_map: OccupyMap, region_bounds: Dictionary) -> Array[Vector2i]:
	if region_bounds["max_x"] < region_bounds["min_x"] or region_bounds["max_y"] < region_bounds["min_y"]:
		return []
	var missing_cells: Array[Vector2i] = []
	for cell_y in range(region_bounds["min_y"], region_bounds["max_y"] + 1):
		for cell_x in range(region_bounds["min_x"], region_bounds["max_x"] + 1):
			var cell := Vector2i(cell_x, cell_y)
			if !occupy_map.has_region_cell(cell):
				missing_cells.append(cell)
	return missing_cells


## 按目标范围优先顺序，每次最多填补指定数量的内部缺失格子。
static func _fill_internal_gaps(
	occupy_map: OccupyMap,
	missing_cells: Array[Vector2i],
	target_bounds: Dictionary,
	max_fill_count: int
) -> bool:
	var prioritized_cells := _sort_internal_gap_cells(missing_cells, target_bounds)
	var fill_cells: Array[Vector2i] = []
	var fill_count := mini(max_fill_count, prioritized_cells.size())
	for cell_index in fill_count:
		fill_cells.append(prioritized_cells[cell_index])
	if fill_cells.is_empty():
		return false
	occupy_map.append_region_cells(fill_cells)
	return true


## 优先返回目标范围内的内部缺失格，其余按 y、x 排序。
static func _sort_internal_gap_cells(missing_cells: Array[Vector2i], target_bounds: Dictionary) -> Array[Vector2i]:
	var target_cells: Array[Vector2i] = []
	var other_cells: Array[Vector2i] = []
	for cell in missing_cells:
		if _is_cell_within_bounds(cell, target_bounds):
			target_cells.append(cell)
		else:
			other_cells.append(cell)
	target_cells.sort_custom(_compare_cells_y_then_x)
	other_cells.sort_custom(_compare_cells_y_then_x)
	target_cells.append_array(other_cells)
	return target_cells


## 获取排序后的首个内部缺失格。
static func _pick_first_internal_gap_cell(missing_cells: Array[Vector2i], region_bounds: Dictionary) -> Vector2i:
	var sorted_cells := _sort_internal_gap_cells(missing_cells, region_bounds)
	return sorted_cells[0]


## 判断格子是否位于指定边界内。
static func _is_cell_within_bounds(cell: Vector2i, bounds: Dictionary) -> bool:
	return (
		cell.x >= bounds["min_x"]
		and cell.x <= bounds["max_x"]
		and cell.y >= bounds["min_y"]
		and cell.y <= bounds["max_y"]
	)


## 按 y 再按 x 排序格子。
static func _compare_cells_y_then_x(cell_a: Vector2i, cell_b: Vector2i) -> bool:
	if cell_a.y < cell_b.y:
		return true
	if cell_a.y == cell_b.y:
		return cell_a.x < cell_b.x
	return false
