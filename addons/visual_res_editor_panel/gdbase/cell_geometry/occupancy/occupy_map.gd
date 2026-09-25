@tool
class_name OccupyMap
extends Resource

#region 信号
## 合法区域发生变化时触发。
signal map_changed
#endregion

#region 枚举
## 自动扩容方向。
enum ExpandDirection {
	X_POSITIVE,
	Y_POSITIVE,
}
#endregion

#region 数据字段
## 合法区域格子集合（权威数据源，注意不要填写重复格子）。
@export var cells: Array[Vector2i]:
	set(value):
		var unique_cells := _unique_cells(value)
		cells = unique_cells
		_sync_region_cells_index()
		_sync_occupancy_with_region()
		_on_map_changed()
## 合法区域索引（由 cells 同步生成，用于快速查询）。
@export var region_cells: Dictionary[Vector2i, Variant] = {}
## 占据索引（cell -> occupant）。
@export var occupied_cells: Dictionary[Vector2i, Variant] = {}
## 反向索引（occupant -> cells），这里没有使用类型字典是因为类型字典不支持 Array。
@export var occupant_to_cells: Dictionary = {}
## 是否启用自动扩容。
@export var is_auto_expand: bool = false
## 自动扩容方向，支持向 X 或向 Y 正方向扩展。
@export var expand_direction: ExpandDirection = ExpandDirection.Y_POSITIVE
## 每次扩容增加的步长（按 expand_direction 生效）。
@export var expand_step: int = 4
## 最大列数上限。-1 表示不限制。
@export var max_expand_width: int = -1
## 最大行数上限。-1 表示不限制。
@export var max_expand_height: int = -1
#endregion


#region 区域初始化
## 向合法区域追加格子，不会清空占据状态，扩容时使用。
func append_region_cells(new_cells: Array[Vector2i]) -> void:
	var merged_cells := cells.duplicate()
	for cell in new_cells:
		if !merged_cells.has(cell):
			merged_cells.append(cell)
	if merged_cells.size() == cells.size():
		return
	cells = _unique_cells(merged_cells)

## 根据 cells 重建 region_cells 索引。
func _sync_region_cells_index() -> void:
	var new_region_cells: Dictionary[Vector2i, Variant] = {}
	for cell in cells:
		new_region_cells[cell] = true
	region_cells = new_region_cells

## 将占据索引裁剪到当前合法区域（移除越界占格，并同步反向索引）。
func _sync_occupancy_with_region() -> void:
	var occupant_list: Array = occupant_to_cells.keys()
	for occupant in occupant_list:
		var occupant_cells: Array = occupant_to_cells[occupant]
		var valid_cells: Array[Vector2i] = []
		for cell in occupant_cells:
			if cell is Vector2i and region_cells.has(cell):
				valid_cells.append(cell)
		if valid_cells.is_empty():
			release_occupant(occupant)
			continue
		if valid_cells.size() == occupant_cells.size():
			continue
		for cell in occupant_cells:
			if cell is Vector2i and !region_cells.has(cell):
				if occupied_cells.has(cell) and occupied_cells[cell] == occupant:
					occupied_cells.erase(cell)
		occupant_to_cells[occupant] = valid_cells
	_remove_occupied_cells_outside_region()

## 清理占据索引中不在合法区域内的残留条目。
func _remove_occupied_cells_outside_region() -> void:
	var stale_cells: Array[Vector2i] = []
	for cell in occupied_cells:
		if !region_cells.has(cell):
			stale_cells.append(cell)
	for cell in stale_cells:
		occupied_cells.erase(cell)

## 去重。
func _unique_cells(input_cells: Array[Vector2i]) -> Array[Vector2i]:
	var unique: Array[Vector2i] = []
	for cell in input_cells:
		if !unique.has(cell):
			unique.append(cell)
	return unique

## 按指定尺寸初始化合法区域（默认从 (0,0) 开始的矩形）。
func init_region_by_size(map_size: Vector2i) -> void:
	var cells_ = _build_region_cells_from_size(map_size)
	set_region_cells(cells_)

## 根据尺寸生成矩形区域格子。
func _build_region_cells_from_size(map_size: Vector2i) -> Array[Vector2i]:
	var built_cells: Array[Vector2i] = []
	for y_index in map_size.y:
		for x_index in map_size.x:
			built_cells.append(Vector2i(x_index, y_index))
	return built_cells

## 设置合法区域（会清空当前占据状态）。
func set_region_cells(new_cells: Array[Vector2i]) -> void:
	cells = _unique_cells(new_cells)
	clear_occupancy()

func _on_map_changed():
	map_changed.emit()
#endregion

#region 占据
## 尝试占据一组格子（如果占据者已经拥有格子,则占据者会先释放旧格子）。
func try_occupy(occupant: Variant, target_cells: Array[Vector2i]) -> bool:
	var unique_cells := _unique_cells(target_cells)
	if !can_occupy(unique_cells, occupant):
		if !is_auto_expand:
			return false
		if !try_expand_for_cells(unique_cells):
			return false
		if !can_occupy(unique_cells, occupant):
			return false
	if occupant_to_cells.has(occupant):
		release_occupant(occupant)
	for cell in unique_cells:
		occupied_cells[cell] = occupant
	occupant_to_cells[occupant] = unique_cells
	return true

## 释放某占据者占据的所有格子。
func release_occupant(occupant: Variant) -> void:
	if !occupant_to_cells.has(occupant):
		return
	var occupant_cells: Array[Vector2i] = occupant_to_cells[occupant]
	for cell in occupant_cells:
		if occupied_cells.has(cell) and occupied_cells[cell] == occupant:
			occupied_cells.erase(cell)
	occupant_to_cells.erase(occupant)

## 清空所有占据（不清区域）。
func clear_occupancy() -> void:
	occupied_cells.clear()
	occupant_to_cells.clear()

## 清空区域与占据。
func clear_all() -> void:
	cells = []
	clear_occupancy()
#endregion

#region 获取区域
func get_map_size() -> Vector2i:
	if cells.is_empty():
		return Vector2i.ZERO
	var min_x: int = cells[0].x
	var max_x: int = cells[0].x
	var min_y: int = cells[0].y
	var max_y: int = cells[0].y
	for cell in cells:
		min_x = mini(min_x, cell.x)
		max_x = maxi(max_x, cell.x)
		min_y = mini(min_y, cell.y)
		max_y = maxi(max_y, cell.y)
	return Vector2i(max_x - min_x + 1, max_y - min_y + 1)

## 获取合法区域边界。
func get_region_bounds() -> Dictionary:
	if cells.is_empty():
		return {
			"min_x": 0,
			"max_x": -1,
			"min_y": 0,
			"max_y": -1,
		}
	var min_x: int = cells[0].x
	var max_x: int = cells[0].x
	var min_y: int = cells[0].y
	var max_y: int = cells[0].y
	for region_cell in cells:
		min_x = mini(min_x, region_cell.x)
		max_x = maxi(max_x, region_cell.x)
		min_y = mini(min_y, region_cell.y)
		max_y = maxi(max_y, region_cell.y)
	return {
		"min_x": min_x,
		"max_x": max_x,
		"min_y": min_y,
		"max_y": max_y,
	}

## 获取当前合法区域。
func get_region_cells() -> Array[Vector2i]:
	return cells.duplicate()
#endregion

#region 获取占据
## 获取某格占据者，不存在返回 null。
func get_occupant(cell: Vector2i) -> Variant:
	if !occupied_cells.has(cell):
		return null
	return occupied_cells[cell]

## 获取某占据者当前占据的所有格子。
func get_cells_of_occupant(occupant: Variant) -> Array[Vector2i]:
	if occupant_to_cells.has(occupant):
		var occupant_cells: Array[Vector2i] = occupant_to_cells[occupant]
		if !occupant_cells.is_empty():
			return occupant_cells.duplicate()
	return _collect_cells_of_occupant_from_occupied_index(occupant)

## 从格子占据索引反查某占据者的格子（资源加载后反向索引可能尚未对齐）。
func _collect_cells_of_occupant_from_occupied_index(occupant: Variant) -> Array[Vector2i]:
	var collected_cells: Array[Vector2i] = []
	if occupant == null:
		return collected_cells
	for occupied_cell in occupied_cells:
		if occupied_cells[occupied_cell] == occupant:
			collected_cells.append(occupied_cell)
	return collected_cells

## 以 occupied_cells 为准重建反向索引，修复场景/资源加载后的索引不一致。
func rebuild_occupant_index() -> void:
	if occupied_cells.is_empty() and !occupant_to_cells.is_empty():
		for occupant in occupant_to_cells.keys():
			var occupant_cells: Array = occupant_to_cells[occupant]
			if occupant_cells == null:
				continue
			for occupant_cell in occupant_cells:
				if occupant_cell is Vector2i:
					occupied_cells[occupant_cell] = occupant
	var rebuilt_occupant_to_cells: Dictionary = {}
	for occupied_cell in occupied_cells:
		var occupant: Variant = occupied_cells[occupied_cell]
		if occupant == null:
			continue
		if !rebuilt_occupant_to_cells.has(occupant):
			var cells_for_occupant: Array[Vector2i] = []
			rebuilt_occupant_to_cells[occupant] = cells_for_occupant
		rebuilt_occupant_to_cells[occupant].append(occupied_cell)
	occupant_to_cells = rebuilt_occupant_to_cells
#endregion

#region 获取空闲格子
## 能够放下该形状的格子组。
func get_free_cells_to_shape_occupy(shape_cells: Array[Vector2i], ignore_occupant: Variant = null) -> Array[Vector2i]:
	var res_cells: Array[Vector2i] = []
	var region: Array[Vector2i] = get_region_cells()
	region.sort_custom(func(vec_a, vec_b):
		if vec_a.y < vec_b.y:
			return true
		elif vec_a.y == vec_b.y and vec_a.x < vec_b.x:
			return true
		else:
			return false)
	for cell in region:
		var new_cells := ShapeTransform.translate_cells(shape_cells, cell)
		if can_occupy(new_cells, ignore_occupant):
			res_cells = new_cells
			break
	return res_cells

## 获取能够放下该形状的形状中心。
func get_free_center_cell_to_shape_occupy(shape_cells: Array[Vector2i], ignore_occupant: Variant = null) -> Vector2i:
	var res_cell: Vector2i = Vector2i(-1, -1)
	var region: Array[Vector2i] = get_region_cells()
	region.sort_custom(func(vec_a, vec_b):
		if vec_a.y < vec_b.y:
			return true
		elif vec_a.y == vec_b.y and vec_a.x < vec_b.x:
			return true
		else:
			return false)
	for cell in region:
		var new_cells := ShapeTransform.translate_cells(shape_cells, cell)
		if can_occupy(new_cells, ignore_occupant):
			res_cell = cell
			break
	if res_cell == Vector2i(-1, -1) and is_auto_expand and region.is_empty():
		_expand_one_step()
		return get_free_center_cell_to_shape_occupy(shape_cells, ignore_occupant)
	elif res_cell == Vector2i(-1, -1) and is_auto_expand:
		var base_cell := _get_expand_base_cell()
		var target_cells := ShapeTransform.translate_cells(shape_cells, base_cell)
		if try_expand_for_cells(target_cells):
			return get_free_center_cell_to_shape_occupy(shape_cells, ignore_occupant)
	return res_cell

## 获取第一个空闲的格子。
func get_first_free_cell() -> Vector2i:
	var res_cell: Vector2i = Vector2i(-1, -1)
	var region: Array[Vector2i] = get_region_cells()
	region.sort_custom(func(vec_a, vec_b):
		if vec_a.y < vec_b.y:
			return true
		elif vec_a.y == vec_b.y and vec_a.x < vec_b.x:
			return true
		else:
			return false)
	for cell in region:
		if !is_occupied(cell):
			res_cell = cell
			break
	if res_cell == Vector2i(-1, -1) and is_auto_expand:
		if _expand_one_step():
			return get_first_free_cell()
	return res_cell
#endregion

#region 判断
## 该变量是否在占位图中占位。
func has_occupant(variant: Variant) -> bool:
	return occupant_to_cells.has(variant)

## 某格是否在合法区域内。
func has_region_cell(cell: Vector2i) -> bool:
	return cells.has(cell)

## 判断合法区域是否包含所有目标格子。
func _contains_all_cells(target_cells: Array[Vector2i]) -> bool:
	for cell in target_cells:
		if !has_region_cell(cell):
			return false
	return true

## 某格是否被占据。
func is_occupied(cell: Vector2i) -> bool:
	return occupied_cells.has(cell)

## 判断占据图是否已满。
func is_full() -> bool:
	if is_auto_expand:
		return false
	return occupied_cells.size() == cells.size()

## 检查一组格子能否被占据。
## ignore_occupant: 检查时可忽略某个占据者（用于“自己移动到新位置”的判定）。
func can_occupy(target_cells: Array[Vector2i], ignore_occupant: Variant = null) -> bool:
	for cell in _unique_cells(target_cells):
		if !region_cells.has(cell):
			return false
		if !occupied_cells.has(cell):
			continue
		if ignore_occupant != null and occupied_cells[cell] == ignore_occupant:
			continue
		return false
	return true

## 判断形状是否能够放入。
func can_shape_occupy(shape_cells: Array[Vector2i], ignore_occupant: Variant = null) -> bool:
	var region: Array[Vector2i] = get_region_cells()
	for cell in region:
		var new_item_cells := ShapeTransform.translate_cells(shape_cells, cell)
		if can_occupy(new_item_cells, ignore_occupant):
			return true
	if is_auto_expand:
		if region.is_empty():
			if !_expand_one_step():
				return false
		else:
			var base_cell := _get_expand_base_cell()
			var target_cells := ShapeTransform.translate_cells(shape_cells, base_cell)
			if !try_expand_for_cells(target_cells):
				return false
		return can_shape_occupy(shape_cells, ignore_occupant)
	return false
#endregion

#region 自动扩容
## 尝试将合法区域扩到可容纳 target_cells。
func try_expand_for_cells(target_cells: Array[Vector2i]) -> bool:
	return OccupyMapExpander.try_expand_for_cells(self, target_cells)

## 扩容一条带：可沿 X 或 Y 正方向扩展，并覆盖目标范围。
func _expand_one_step(target_min_x: int = 0, target_max_x: int = 0, target_min_y: int = 0, target_max_y: int = 0) -> bool:
	return OccupyMapExpander.expand_one_step(self, target_min_x, target_max_x, target_min_y, target_max_y)

## 获取下一次扩容时用于放置形状的基准格子。
func _get_expand_base_cell() -> Vector2i:
	return OccupyMapExpander.get_expand_base_cell(self)
#endregion
