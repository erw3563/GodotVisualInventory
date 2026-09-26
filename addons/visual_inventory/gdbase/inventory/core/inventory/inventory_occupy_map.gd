@tool
class_name InventoryOccupyMap
extends OccupyMap
## InventoryOccupyMap 是 InventoryData 专用的占位图资源。
## 该类在 OccupyMap 的基础上，提供 ItemInstanceData 友好的方法。
## 默认按形状占位规则工作；非形状行为由 NonShapeInventoryOccupyMap 覆盖。

#region 信号
## 物品实例首次注册到占位图时触发。
signal item_instance_added(item_instance_data: ItemInstanceData)
## 物品实例从占位图移除时触发（removed_center_cell 为移除前的中心格坐标）。
signal item_instance_removed(item_instance_data: ItemInstanceData, removed_center_cell: Vector2i)
## 物品实例在占位图内的中心格位置发生变化时触发（previous_cell 为变化前的中心格坐标）。
signal item_instance_position_changed(item_instance_data: ItemInstanceData, previous_cell: Vector2i)
## 物品实例在占位图内旋转时触发。
signal item_instance_rotated(item_instance_data: ItemInstanceData)
## 物品实例在占位图内轮廓变形时触发。
signal item_instance_reshaped(item_instance_data: ItemInstanceData)
## 单个物品实例占位校正完成时触发（重叠或越界坐标已重新注册）。
signal item_instance_corrected(item_instance_data: ItemInstanceData, previous_cell: Vector2i)
## 无法找到合法位置处理该物品实例时触发（重叠或越界且背包无可用空位）。
signal item_instance_cannot_be_handled(item_instance_data: ItemInstanceData)
#endregion

#region 数据字段
## 已放置列表：仅作 occupancy 派生缓存，成员权威为 occupied_cells。
@export var placed_item_instances: Array[ItemInstanceData] = []
## 校正失败溢出列表（不在 occupancy 中，不计入背包成员）。
@export var unplaced_item_instances: Array[ItemInstanceData] = []
## 物品实例到其注册中心格的映射，用于在移除时获取稳定的原位置。
var occupant_to_center_cell: Dictionary = {}
#endregion

#region 占格虚方法（默认形状逻辑）
## 空间格位是否具有邻接和路径语义；非空间实现覆盖此协议。
func is_spatial() -> bool:
	return true

## 获取物品在指定中心格应占据的格子（形状：按轮廓；非形状：仅中心格）。
func get_occupy_cells_for_item(
	item_instance_data: ItemInstanceData,
	center_cell: Vector2i
) -> Array[Vector2i]:
	if item_instance_data == null:
		return []
	return item_instance_data.get_cells(center_cell)


## 获取物品在指定朝向与中心格应占据的格子。
func get_occupy_cells_for_item_with_dir(
	item_instance_data: ItemInstanceData,
	target_dir: Vector2,
	center_cell: Vector2i
) -> Array[Vector2i]:
	if item_instance_data == null:
		return []
	return item_instance_data.get_cells_with_dir(target_dir, center_cell)


## 获取放置预览格子（默认与占格一致）。
func get_preview_cells_for_item(
	item_instance_data: ItemInstanceData,
	center_cell: Vector2i
) -> Array[Vector2i]:
	return get_occupy_cells_for_item(item_instance_data, center_cell)


## 获取可放下物品的格子与朝向；返回 Dictionary：cell（Vector2i）、dir（Vector2）。
func get_free_placement_for_item(
	item_instance_data: ItemInstanceData,
	prefer_current_position: bool = true
) -> Dictionary:
	return InventoryOccupyMapQuery.get_free_cell_to_place_item_with_rotations(
		self, item_instance_data, prefer_current_position
	)


## 判断在不进行融合时是否还能放入该物品。
func can_add_item_without_merge(item_instance_data: ItemInstanceData) -> bool:
	if is_full():
		return false
	return InventoryOccupyMapQuery.can_shape_occupy_with_rotations(self, item_instance_data)


## 判断物品实例在当前占位状态下是否需要校正。
func does_item_instance_need_correction(
	item_instance_data: ItemInstanceData,
	target_cell: Vector2i,
	target_dir = null
) -> bool:
	if !occupant_to_cells.has(item_instance_data):
		return true
	if get_item_center_cell(item_instance_data) != target_cell:
		return true
	return InventoryOccupyMapQuery.does_shape_item_instance_need_correction(
		self, item_instance_data, target_cell, target_dir
	)


## 获取换成新轮廓后的目标占据格子（默认按形状轮廓计算）。
func get_target_cells_for_reshape(
	item_instance_data: ItemInstanceData,
	new_shape: Shape
) -> Array[Vector2i]:
	if item_instance_data == null or new_shape == null:
		return []
	var center_cell := get_item_center_cell(item_instance_data)
	if center_cell == Vector2i(-1, -1):
		return []
	return item_instance_data.get_cells_for_shape(new_shape, item_instance_data.dir, center_cell)


## 判断物品换成新轮廓后是否仍可占据当前中心格。
func can_reshape_item_in_place(
	item_instance_data: ItemInstanceData,
	new_shape: Shape
) -> bool:
	var target_cells := get_target_cells_for_reshape(item_instance_data, new_shape)
	if target_cells.is_empty():
		return false
	return can_occupy(target_cells, item_instance_data)
#endregion

#region 区域初始化
## 初始化合法区域格子（会清空占据状态）。
func init_occupy_map(init_cells: Array[Vector2i] = []) -> void:
	if init_cells.is_empty():
		set_region_cells([Vector2i.ZERO])
	else:
		set_region_cells(init_cells)
#endregion

#region 校正
func _on_map_changed():
	super._on_map_changed()
	process_wrong_item_instances()

## 处理错误的物品实例：移除数量为 0 的成员，并修正重叠或越界占位。
func process_wrong_item_instances() -> void:
	for item_instance_data in get_occupants_from_occupancy().duplicate():
		process_wrong_item_instance(item_instance_data)
	for item_instance_data in unplaced_item_instances.duplicate():
		process_wrong_item_instance(item_instance_data)

## 校正单个物品实例的占位；数量为 0 时直接移除。成功校正返回 true，无需校正、移除或失败返回 false。
func process_wrong_item_instance(item_instance_data: ItemInstanceData) -> bool:
	if item_instance_data == null:
		return false
	if item_instance_data.num == 0:
		_remove_zero_num_item_instance(item_instance_data)
		return false
	return _process_wrong_item_instance_by_mode(item_instance_data)


## 按当前占位模式校正物品（默认形状：支持自动旋转寻位）。
func _process_wrong_item_instance_by_mode(item_instance_data: ItemInstanceData) -> bool:
	var placement := get_free_placement_for_item(item_instance_data, true)
	if placement.cell == Vector2i(-1, -1):
		_handle_item_instance_cannot_be_placed(item_instance_data)
		return false
	if does_item_instance_need_correction(
			item_instance_data, placement.cell, placement.dir):
		var previous_cell := get_item_center_cell(item_instance_data)
		if !try_register_item_instance_at_placement(
				item_instance_data, placement.cell, placement.dir):
			return false
		item_instance_corrected.emit(item_instance_data, previous_cell)
	return true

## 移除数量为 0 的物品（已占位则走取出；仅在未放置列表则直接剔除）。
func _remove_zero_num_item_instance(item_instance_data: ItemInstanceData) -> void:
	if item_instance_data == null:
		return
	if occupant_to_cells.has(item_instance_data):
		try_take_item_instance(item_instance_data)
		return
	placed_item_instances.erase(item_instance_data)
	unplaced_item_instances.erase(item_instance_data)

## 将无法放置的物品移入未放置列表并发出信号。
func _handle_item_instance_cannot_be_placed(item_instance_data: ItemInstanceData) -> void:
	if item_instance_data == null:
		return
	placed_item_instances.erase(item_instance_data)
	if !unplaced_item_instances.has(item_instance_data):
		unplaced_item_instances.append(item_instance_data)
	item_instance_cannot_be_handled.emit(item_instance_data)
	print("物品 |" + item_instance_data.get_item_name() + "| 因空间不足而无法放置。")
#endregion

#region 占据
## 尝试占据一组格子（列表维护由上层交互方法在成功后负责）。
func try_occupy(occupant: Variant, target_cells: Array[Vector2i]) -> bool:
	if !occupant is ItemInstanceData:
		return false
	var item_instance_data := occupant as ItemInstanceData
	if super.try_occupy(item_instance_data, target_cells):
		return true
	else:
		return false

## 释放某占据者占据的所有格子。
func release_occupant(occupant: Variant) -> void:
	if !occupant_to_cells.has(occupant):
		return
	super.release_occupant(occupant)
	occupant_to_center_cell.erase(occupant)


## 清空所有占据并同步清理中心格映射与已放置缓存。
func clear_occupancy() -> void:
	super.clear_occupancy()
	occupant_to_center_cell.clear()
	placed_item_instances.clear()

## 清空全部区域和占据并同步清理中心格映射。
func clear_all() -> void:
	super.clear_all()
	occupant_to_center_cell.clear()
	placed_item_instances.clear()
	unplaced_item_instances.clear()

## 尝试将物品实例注册到可用中心格（自动选择位置）。
func try_register_item_instance_at_free_cell(
	item_instance_data: ItemInstanceData,
	prefer_current_position: bool = true
) -> bool:
	var placement := get_free_placement_for_item(item_instance_data, prefer_current_position)
	return try_register_item_instance_at_placement(
		item_instance_data, placement.cell, placement.dir
	)

#region 重排
## 尝试重新布局物品实例（忽略当前坐标，重新寻找可用位置）。
## previous_center_cell 有效时视为已知旧位的重排：成功后发 position_changed，不发 added。
## previous_center_cell 为 (-1, -1) 时等同普通 register（可发 added）。
func try_relayout_item_instance(
	item_instance_data: ItemInstanceData,
	previous_center_cell: Vector2i = Vector2i(-1, -1)
) -> bool:
	if item_instance_data == null:
		return false
	if previous_center_cell == Vector2i(-1, -1):
		return try_register_item_instance_at_free_cell(item_instance_data, false)
	return _try_relayout_item_instance_from_previous(item_instance_data, previous_center_cell)

## 按已知旧中心格重排：占据成功后仅发位置变化信号。
func _try_relayout_item_instance_from_previous(
	item_instance_data: ItemInstanceData,
	previous_center_cell: Vector2i
) -> bool:
	var placement := get_free_placement_for_item(item_instance_data, false)
	if placement.cell == Vector2i(-1, -1):
		return false
	return _try_place_item_instance_for_relayout(
		item_instance_data, placement.cell, placement.dir, previous_center_cell
	)

## 为重排占据指定格：不发 added；中心格变化时发 position_changed；朝向变化时发 rotated。
func _try_place_item_instance_for_relayout(
	item_instance_data: ItemInstanceData,
	target_cell: Vector2i,
	target_dir: Vector2,
	previous_center_cell: Vector2i
) -> bool:
	if target_cell == Vector2i(-1, -1):
		return false
	var original_dir := item_instance_data.dir
	var normalized_target_dir := ShapeTransform.normalize_cardinal_dir(target_dir)
	item_instance_data.dir = normalized_target_dir
	if !InventoryOccupyMapQuery.can_place_item_in_cell(self, item_instance_data, target_cell):
		item_instance_data.dir = original_dir
		return false
	var target_cells := get_occupy_cells_for_item(item_instance_data, target_cell)
	if !try_occupy(item_instance_data, target_cells):
		item_instance_data.dir = original_dir
		return false
	_sync_item_instance_center_cell(item_instance_data, target_cell)
	_add_to_placed_item_instance(item_instance_data)
	if previous_center_cell != target_cell:
		item_instance_position_changed.emit(item_instance_data, previous_center_cell)
	if normalized_target_dir != original_dir:
		item_instance_rotated.emit(item_instance_data)
	return true
#endregion

#region 获取占据
## 获取物品实例在占位图中的中心格坐标；未注册占位时返回 Vector2i(-1, -1)。
func get_item_center_cell(item_instance_data: ItemInstanceData) -> Vector2i:
	if item_instance_data == null:
		return Vector2i(-1, -1)
	if occupant_to_center_cell.has(item_instance_data):
		return occupant_to_center_cell[item_instance_data]
	var inferred_center_cell := _infer_item_center_cell_from_occupancy(item_instance_data)
	if inferred_center_cell != Vector2i(-1, -1):
		occupant_to_center_cell[item_instance_data] = inferred_center_cell
	return inferred_center_cell

## 重建运行时中心格索引，并清理空占位条目。
func rebuild_runtime_indexes() -> void:
	rebuild_occupant_index()
	occupant_to_center_cell.clear()
	for occupant in occupant_to_cells.keys():
		if occupant is ItemInstanceData:
			var inferred_center_cell := _infer_item_center_cell_from_occupancy(occupant)
			if inferred_center_cell != Vector2i(-1, -1):
				occupant_to_center_cell[occupant] = inferred_center_cell

## 按当前占据索引重建已放置缓存（occupancy 胜出，覆盖旧列表）。
func sync_placed_list_from_occupancy() -> void:
	placed_item_instances.clear()
	for occupant in get_occupants_from_occupancy():
		_add_to_placed_item_instance(occupant)

## 从当前占据索引收集已放置物品实例（背包成员权威枚举）。
func get_occupants_from_occupancy() -> Array[ItemInstanceData]:
	var occupants: Array[ItemInstanceData] = []
	var seen_occupants: Dictionary = {}
	for occupied_cell in occupied_cells:
		var occupant: Variant = occupied_cells[occupied_cell]
		if occupant is ItemInstanceData and !seen_occupants.has(occupant):
			seen_occupants[occupant] = true
			occupants.append(occupant)
	if !occupants.is_empty():
		return occupants
	for occupant in occupant_to_cells.keys():
		if occupant is ItemInstanceData and !seen_occupants.has(occupant):
			var occupant_cells: Array = occupant_to_cells[occupant]
			if occupant_cells is Array and occupant_cells.is_empty():
				continue
			seen_occupants[occupant] = true
			occupants.append(occupant)
	return occupants

## 背包成员枚举别名：等同 get_occupants_from_occupancy。
func get_item_instances_from_occupancy() -> Array[ItemInstanceData]:
	return get_occupants_from_occupancy()

## 判断物品实例是否在 occupancy 中（权威成员判定）。
func has_item_instance_in_occupancy(item_instance_data: ItemInstanceData) -> bool:
	if item_instance_data == null:
		return false
	if occupant_to_cells.has(item_instance_data):
		var occupant_cells: Array = occupant_to_cells[item_instance_data]
		if occupant_cells is Array and !occupant_cells.is_empty():
			return true
	for occupied_cell in occupied_cells:
		if occupied_cells[occupied_cell] == item_instance_data:
			return true
	return false

## 获取指定格子中的物品实例。
func get_item_in_cell(cell: Vector2i) -> ItemInstanceData:
	return get_occupant(cell) as ItemInstanceData
#endregion

#region 物品列表维护
## 将物品实例登记为已放置，并从未放置列表移除。
func _add_to_placed_item_instance(item_instance_data: ItemInstanceData) -> void:
	if item_instance_data == null:
		return
	unplaced_item_instances.erase(item_instance_data)
	if !placed_item_instances.has(item_instance_data):
		placed_item_instances.append(item_instance_data)
#endregion

#region 交互
## 记录物品实例在占位图中的中心格坐标。
func _sync_item_instance_center_cell(item_instance_data: ItemInstanceData, center_cell: Vector2i) -> void:
	occupant_to_center_cell[item_instance_data] = center_cell

## 尝试将物品实例按指定中心格与朝向注册到占位图。
func try_register_item_instance_at_placement(
	item_instance_data: ItemInstanceData,
	target_cell: Vector2i,
	target_dir: Vector2
) -> bool:
	if item_instance_data == null or target_cell == Vector2i(-1, -1):
		return false
	var original_dir := item_instance_data.dir
	var normalized_target_dir := ShapeTransform.normalize_cardinal_dir(target_dir)
	var is_already_placed := occupant_to_cells.has(item_instance_data)
	var previous_cell := get_item_center_cell(item_instance_data) if is_already_placed else Vector2i(-1, -1)
	item_instance_data.dir = normalized_target_dir
	if !InventoryOccupyMapQuery.can_place_item_in_cell(self, item_instance_data, target_cell):
		item_instance_data.dir = original_dir
		return false
	var target_cells := get_occupy_cells_for_item(item_instance_data, target_cell)
	if !try_occupy(item_instance_data, target_cells):
		item_instance_data.dir = original_dir
		return false
	_sync_item_instance_center_cell(item_instance_data, target_cell)
	_add_to_placed_item_instance(item_instance_data)
	if is_already_placed:
		if previous_cell != target_cell:
			item_instance_position_changed.emit(item_instance_data, previous_cell)
	else:
		item_instance_added.emit(item_instance_data)
	if normalized_target_dir != original_dir:
		item_instance_rotated.emit(item_instance_data)
	return true

## 尝试旋转占位图中的物品实例（默认顺时针 90 度）。
func try_rotate_item_instance(item_instance_data: ItemInstanceData, rotate_step: int = 1) -> bool:
	if item_instance_data == null or !occupant_to_cells.has(item_instance_data):
		return false
	if !InventoryOccupyMapQuery.can_rotate_item_in_place(self, item_instance_data, rotate_step):
		return false
	var center_cell := get_item_center_cell(item_instance_data)
	var target_dir := ShapeTransform.rotate_dir_clockwise(item_instance_data.dir, rotate_step)
	var target_cells := get_occupy_cells_for_item_with_dir(
		item_instance_data, target_dir, center_cell
	)
	if target_cells.is_empty():
		return false
	if !try_occupy(item_instance_data, target_cells):
		return false
	item_instance_data.dir = target_dir
	_sync_item_instance_center_cell(item_instance_data, center_cell)
	_add_to_placed_item_instance(item_instance_data)
	item_instance_rotated.emit(item_instance_data)
	return true

## 尽力旋转占位图中的物品实例，依次尝试 90°、180°、270° 旋转。
func try_rotate_item_instance_best_effort(item_instance_data: ItemInstanceData) -> bool:
	for rotate_step in [1, 2, 3]:
		if try_rotate_item_instance(item_instance_data, rotate_step):
			return true
	return false

## 安装处理器的已准备状态与占位，中心格和朝向不变；不创建 ShapeState。
func try_reshape_item_instance(item_instance_data: ItemInstanceData, prepared_states: Array[ItemInstanceState]) -> bool:
	if item_instance_data == null:
		return false
	var projected := ItemInstanceData.new()
	projected.item_data = item_instance_data.item_data
	projected.instance_states = prepared_states
	var result := projected.get_shape_state()
	if not item_instance_data.is_valid_reshape_result(result):
		return false
	var new_shape := result.runtime_shape
	if !occupant_to_cells.has(item_instance_data):
		return false
	if !can_reshape_item_in_place(item_instance_data, new_shape):
		return false
	var center_cell := get_item_center_cell(item_instance_data)
	var target_cells := get_target_cells_for_reshape(item_instance_data, new_shape)
	if target_cells.is_empty():
		return false
	if !try_occupy(item_instance_data, target_cells):
		return false
	item_instance_data.instance_states = prepared_states
	item_instance_data._mark_instance_states_ready()
	item_instance_data.shape_changed.emit()
	_sync_item_instance_center_cell(item_instance_data, center_cell)
	_add_to_placed_item_instance(item_instance_data)
	item_instance_reshaped.emit(item_instance_data)
	return true

## 尝试为物品实例注册占据位置。
func try_add_item_instance(item_instance_data: ItemInstanceData) -> bool:
	return try_register_item_instance_at_free_cell(item_instance_data)

## 尝试将物品实例放置到指定中心格（仅适用于尚未注册在位图中的物品）。
func try_place_item_instance_in_cell(item_instance_data: ItemInstanceData, center_cell: Vector2i) -> bool:
	if item_instance_data == null or occupant_to_cells.has(item_instance_data):
		return false
	if !InventoryOccupyMapQuery.can_place_item_in_cell(self, item_instance_data, center_cell):
		return false
	if try_occupy(item_instance_data, get_occupy_cells_for_item(item_instance_data, center_cell)):
		_sync_item_instance_center_cell(item_instance_data, center_cell)
		_add_to_placed_item_instance(item_instance_data)
		item_instance_added.emit(item_instance_data)
		return true
	return false

## 尝试从占位图中移除物品实例。
func try_remove_item_instance(item_instance_data: ItemInstanceData) -> bool:
	if item_instance_data == null or !occupant_to_cells.has(item_instance_data):
		return false
	var removed_center_cell := get_item_center_cell(item_instance_data)
	release_occupant(item_instance_data)
	placed_item_instances.erase(item_instance_data)
	unplaced_item_instances.erase(item_instance_data)
	item_instance_removed.emit(item_instance_data, removed_center_cell)
	return true

## 尝试从占位图中拿取物品实例。
func try_take_item_instance(item_instance_data: ItemInstanceData) -> bool:
	return try_remove_item_instance(item_instance_data)

## 尝试将位图内的物品实例移动到指定中心格。
func try_move_item_instance_to_cell(item_instance_data: ItemInstanceData, center_cell: Vector2i) -> bool:
	if item_instance_data == null or !occupant_to_cells.has(item_instance_data):
		return false

	var previous_cell := get_item_center_cell(item_instance_data)
	if previous_cell == center_cell:
		return true

	if InventoryOccupyMapQuery.can_place_item_in_cell(self, item_instance_data, center_cell):
		if try_occupy(item_instance_data, get_occupy_cells_for_item(item_instance_data, center_cell)):
			_sync_item_instance_center_cell(item_instance_data, center_cell)
			_add_to_placed_item_instance(item_instance_data)
			item_instance_position_changed.emit(item_instance_data, previous_cell)
			return true
	return false

## 尝试将物品实例与目标格子处的物品实例合并。
func try_merge_item_instance_in_cell(item_instance_data: ItemInstanceData, cell: Vector2i) -> bool:
	if item_instance_data == null:
		return false
	if !InventoryOccupyMapQuery.can_merge_item_in_cell(self, item_instance_data, cell):
		return false
	var target_item := get_item_in_cell(cell)
	if target_item == null or target_item == item_instance_data:
		return false
	if !target_item.try_merge_item(item_instance_data):
		return false
	if item_instance_data.num == 0 and occupant_to_cells.has(item_instance_data):
		try_remove_item_instance(item_instance_data)
	return true

## 尝试用物品实例替换目标格范围内的唯一物品，成功时返回被替换出的物品实例。
func try_replace_item_instance_in_cell(item_instance_data: ItemInstanceData, center_cell: Vector2i) -> ItemInstanceData:
	var replace_target := InventoryOccupyMapQuery.get_replace_target_item(self, item_instance_data, center_cell)
	if replace_target == null:
		return null
	var replaced_center_cell := get_item_center_cell(replace_target)
	if try_remove_item_instance(replace_target):
		var is_placed := false
		if occupant_to_cells.has(item_instance_data):
			is_placed = try_move_item_instance_to_cell(item_instance_data, center_cell)
		else:
			is_placed = try_place_item_instance_in_cell(item_instance_data, center_cell)
		if !is_placed:
			try_place_item_instance_in_cell(replace_target, replaced_center_cell)
			return null
		return replace_target
	else:
		return null

## 根据当前占据格子反推物品实例的中心格（默认按形状轮廓反推）。
## 占据格顺序经 .tres 序列化或 rebuild_occupant_index 重建后不保证与形状定义
## 对齐，因此逐个候选锚点尝试，取能完整还原占据集合的那个中心。
func _infer_item_center_cell_from_occupancy(item_instance_data: ItemInstanceData) -> Vector2i:
	var occupied_item_cells := get_cells_of_occupant(item_instance_data)
	if occupied_item_cells.is_empty():
		return Vector2i(-1, -1)
	if occupied_item_cells.size() == 1:
		return occupied_item_cells[0]
	var local_cells: Array[Vector2i] = item_instance_data.get_local_cells()
	var rotated_local_cells := ShapeTransform.rotate_cells_by_dir(local_cells, item_instance_data.dir)
	for anchor_index in rotated_local_cells.size():
		var inferred_center_cell := occupied_item_cells[0] - rotated_local_cells[anchor_index]
		if _are_cell_sets_equal(
				get_occupy_cells_for_item(item_instance_data, inferred_center_cell),
				occupied_item_cells):
			return inferred_center_cell
	return Vector2i(-1, -1)

## 判断两组格子坐标是否表示同一占据区域。
func _are_cell_sets_equal(cells_a: Array[Vector2i], cells_b: Array[Vector2i]) -> bool:
	if cells_a.size() != cells_b.size():
		return false
	for cell in cells_a:
		if !cells_b.has(cell):
			return false
	return true
#endregion
