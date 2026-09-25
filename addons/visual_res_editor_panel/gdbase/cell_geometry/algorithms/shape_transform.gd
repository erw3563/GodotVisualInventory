class_name ShapeTransform
extends RefCounted

## 将方向规范化为四向单位向量，无效时默认返回 Vector2.RIGHT。
static func normalize_cardinal_dir(direction: Vector2) -> Vector2:
	var rounded_direction := Vector2i(roundi(direction.x), roundi(direction.y))
	if abs(rounded_direction.x) + abs(rounded_direction.y) != 1:
		return Vector2.RIGHT
	return Vector2(rounded_direction)

## 将旋转次数转换为对应的四向单位向量。
static func rotate_num_to_dir(rotate_num: int) -> Vector2:
	match posmod(rotate_num, 4):
		0:
			return Vector2.RIGHT
		1:
			return Vector2.DOWN
		2:
			return Vector2.LEFT
		3:
			return Vector2.UP
	return Vector2.RIGHT

## 将四向单位向量转换为旋转次数。
static func dir_to_rotate_num(direction: Vector2) -> int:
	match normalize_cardinal_dir(direction):
		Vector2.RIGHT:
			return 0
		Vector2.DOWN:
			return 1
		Vector2.LEFT:
			return 2
		Vector2.UP:
			return 3
	return 0

## 将方向顺时针旋转指定次数。
static func rotate_dir_clockwise(direction: Vector2, steps: int = 1) -> Vector2:
	return rotate_num_to_dir(dir_to_rotate_num(direction) + steps)

## 将方向转换为 UI 显示用的顺时针旋转弧度。
static func dir_to_rotation_angle(direction: Vector2) -> float:
	return PI / 2.0 * dir_to_rotate_num(direction)

## 将单个格子按 90 度整数旋转，rotate_num 可为任意整数。
static func rotate_cell_90(cell: Vector2i, rotate_num: int) -> Vector2i:
	var normalized_rotate_num := posmod(rotate_num, 4)
	match normalized_rotate_num:
		0:
			return cell
		1:
			return Vector2i(-cell.y, cell.x)
		2:
			return Vector2i(-cell.x, -cell.y)
		3:
			return Vector2i(cell.y, -cell.x)
	return cell

## 将单个格子按四向朝向旋转。
static func rotate_cell_by_dir(cell: Vector2i, direction: Vector2) -> Vector2i:
	return rotate_cell_90(cell, dir_to_rotate_num(direction))

## 将物品局部方向换算为背包网格方向。
static func to_world_direction(local_direction: Vector2i, rotate_num: int) -> Vector2i:
	return rotate_cell_90(local_direction, rotate_num)

## 将物品局部方向按物品朝向换算为背包网格方向。
static func to_world_direction_with_dir(local_direction: Vector2i, item_direction: Vector2) -> Vector2i:
	return rotate_cell_by_dir(local_direction, item_direction)

## 批量旋转格子。
static func rotate_cells_90(cells: Array[Vector2i], rotate_num: int) -> Array[Vector2i]:
	if posmod(rotate_num, 4) == 0:
		return cells.duplicate()
	var result: Array[Vector2i] = []
	result.resize(cells.size())
	for index in range(cells.size()):
		result[index] = rotate_cell_90(cells[index], rotate_num)
	return result

## 批量按四向朝向旋转格子。
static func rotate_cells_by_dir(cells: Array[Vector2i], direction: Vector2) -> Array[Vector2i]:
	return rotate_cells_90(cells, dir_to_rotate_num(direction))

## 批量平移格子。
static func translate_cells(cells: Array[Vector2i], offset: Vector2i) -> Array[Vector2i]:
	if offset == Vector2i.ZERO:
		return cells.duplicate()
	var result: Array[Vector2i] = []
	result.resize(cells.size())
	for index in range(cells.size()):
		result[index] = cells[index] + offset
	return result

## 组合变换：先旋转后平移。
static func transform_cells(cells: Array[Vector2i], rotate_num: int, offset: Vector2i = Vector2i.ZERO) -> Array[Vector2i]:
	var rotated_cells := rotate_cells_90(cells, rotate_num)
	return translate_cells(rotated_cells, offset)

## 组合变换：先按方向旋转后平移。
static func transform_cells_with_dir(cells: Array[Vector2i], direction: Vector2, offset: Vector2i = Vector2i.ZERO) -> Array[Vector2i]:
	var rotated_cells := rotate_cells_by_dir(cells, direction)
	return translate_cells(rotated_cells, offset)

## 从轮廓取局部格子；空轮廓回退原点。
static func cells_from_shape(shape: Shape) -> Array[Vector2i]:
	if shape != null:
		var shape_cells := shape.get_cells()
		if !shape_cells.is_empty():
			return shape_cells
	return [Vector2i.ZERO]

## 按局部格子、朝向与中心格预览占据。
static func transform_local_cells(
	local_cells: Array[Vector2i],
	direction: Vector2,
	center: Vector2i = Vector2i.ZERO
) -> Array[Vector2i]:
	var source_cells := local_cells if !local_cells.is_empty() else [Vector2i.ZERO]
	var normalized_direction := normalize_cardinal_dir(direction)
	return transform_cells_with_dir(source_cells, normalized_direction, center)

## 局部格子的轴对齐包围盒尺寸。
static func bounding_size(local_cells: Array[Vector2i]) -> Vector2i:
	return bounding_rect(local_cells).size

## 局部格子的轴对齐包围盒（min 角 + 尺寸）；空集回退原点单格。
## min 角相对格子自身的原点，可为负（形状向左上延伸时）。
static func bounding_rect(local_cells: Array[Vector2i]) -> Rect2i:
	if local_cells.is_empty():
		return Rect2i(Vector2i.ZERO, Vector2i.ONE)
	var min_x := local_cells[0].x
	var max_x := local_cells[0].x
	var min_y := local_cells[0].y
	var max_y := local_cells[0].y
	for cell in local_cells:
		min_x = mini(min_x, cell.x)
		max_x = maxi(max_x, cell.x)
		min_y = mini(min_y, cell.y)
		max_y = maxi(max_y, cell.y)
	return Rect2i(Vector2i(min_x, min_y), Vector2i(max_x - min_x + 1, max_y - min_y + 1))

## 物品原点格按朝向变换后的坐标。
static func origin_cell(direction: Vector2, center: Vector2i = Vector2i.ZERO) -> Vector2i:
	var transformed_cells := transform_cells_with_dir([Vector2i.ZERO], direction, center)
	return transformed_cells[0]

## 两组格子是否表示同一轮廓（集合相等）。
static func are_cell_sets_equal(cells_a: Array[Vector2i], cells_b: Array[Vector2i]) -> bool:
	if cells_a.size() != cells_b.size():
		return false
	for cell in cells_a:
		if !cells_b.has(cell):
			return false
	return true
