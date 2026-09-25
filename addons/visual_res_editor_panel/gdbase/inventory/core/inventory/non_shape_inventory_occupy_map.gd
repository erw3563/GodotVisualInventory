@tool
class_name NonShapeInventoryOccupyMap
extends InventoryOccupyMap
## 非形状占位图：物品永远只占中心格一格，忽略轮廓与旋转扩格。
## 旋转仅修改朝向 dir；不支持轮廓变形。

#region 占格虚方法
func is_spatial() -> bool:
	return false

## 非形状永远只占中心格。
func get_occupy_cells_for_item(
	_item_instance_data: ItemInstanceData,
	center_cell: Vector2i
) -> Array[Vector2i]:
	return [center_cell]


## 非形状忽略朝向，仍只占中心格。
func get_occupy_cells_for_item_with_dir(
	_item_instance_data: ItemInstanceData,
	_target_dir: Vector2,
	center_cell: Vector2i
) -> Array[Vector2i]:
	return [center_cell]


## 预览固定为一格。
func get_preview_cells_for_item(
	item_instance_data: ItemInstanceData,
	center_cell: Vector2i
) -> Array[Vector2i]:
	return get_occupy_cells_for_item(item_instance_data, center_cell)


## 寻位：优先当前格，否则取第一个空闲格；保留当前朝向。
func get_free_placement_for_item(
	item_instance_data: ItemInstanceData,
	prefer_current_position: bool = true
) -> Dictionary:
	var original_dir := Vector2.DOWN
	if item_instance_data != null:
		original_dir = item_instance_data.dir
	var free_cell := InventoryOccupyMapQuery.get_free_cell_to_place_non_shape_item(
		self, item_instance_data, prefer_current_position
	)
	return {"cell": free_cell, "dir": original_dir}


## 非形状：只要未满即可放入（不检查轮廓）。
func can_add_item_without_merge(_item_instance_data: ItemInstanceData) -> bool:
	return !is_full()


## 非形状校正判定：越界或该格占用者不是自己。
func does_item_instance_need_correction(
	item_instance_data: ItemInstanceData,
	target_cell: Vector2i,
	_target_dir = null
) -> bool:
	if !occupant_to_cells.has(item_instance_data):
		return true
	if get_item_center_cell(item_instance_data) != target_cell:
		return true
	return InventoryOccupyMapQuery.does_non_shape_item_instance_need_correction(
		self, item_instance_data, target_cell
	)


## 非形状不支持变形，目标格为空。
func get_target_cells_for_reshape(
	_item_instance_data: ItemInstanceData,
	_new_shape: Shape
) -> Array[Vector2i]:
	return []


## 非形状不支持轮廓变形。
func can_reshape_item_in_place(
	_item_instance_data: ItemInstanceData,
	_new_shape: Shape
) -> bool:
	return false
#endregion

#region 校正
## 非形状校正：单格寻位后移动或放置。
func _process_wrong_item_instance_by_mode(item_instance_data: ItemInstanceData) -> bool:
	var placement := get_free_placement_for_item(item_instance_data, true)
	if placement.cell == Vector2i(-1, -1):
		_handle_item_instance_cannot_be_placed(item_instance_data)
		return false
	if does_item_instance_need_correction(item_instance_data, placement.cell, placement.dir):
		var previous_cell := get_item_center_cell(item_instance_data)
		var is_corrected := false
		if occupant_to_cells.has(item_instance_data):
			is_corrected = try_move_item_instance_to_cell(item_instance_data, placement.cell)
		else:
			is_corrected = try_place_item_instance_in_cell(item_instance_data, placement.cell)
		if !is_corrected:
			return false
		item_instance_corrected.emit(item_instance_data, previous_cell)
	return true
#endregion

#region 交互
## 旋转只改朝向，占格仍为一格。
func try_rotate_item_instance(item_instance_data: ItemInstanceData, rotate_step: int = 1) -> bool:
	if item_instance_data == null or !occupant_to_cells.has(item_instance_data):
		return false
	if rotate_step == 0:
		return true
	var center_cell := get_item_center_cell(item_instance_data)
	if center_cell == Vector2i(-1, -1):
		return false
	var target_dir := ShapeTransform.rotate_dir_clockwise(item_instance_data.dir, rotate_step)
	var target_cells := get_occupy_cells_for_item(item_instance_data, center_cell)
	if !try_occupy(item_instance_data, target_cells):
		return false
	item_instance_data.dir = target_dir
	_sync_item_instance_center_cell(item_instance_data, center_cell)
	_add_to_placed_item_instance(item_instance_data)
	item_instance_rotated.emit(item_instance_data)
	return true


## 非形状不支持轮廓变形。
func try_reshape_item_instance(
	_item_instance_data: ItemInstanceData,
	_prepared_states: Array[ItemInstanceState]
) -> bool:
	return false


## 非形状中心格即为占用的那一格。
func _infer_item_center_cell_from_occupancy(item_instance_data: ItemInstanceData) -> Vector2i:
	var occupied_item_cells := get_cells_of_occupant(item_instance_data)
	if occupied_item_cells.is_empty():
		return Vector2i(-1, -1)
	return occupied_item_cells[0]
#endregion
