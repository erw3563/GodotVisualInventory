extends RefCounted
class_name ShapeCells

## 获取中心周围菱形地块
static func get_diamond_cells(center_cell:Vector2i,size:int)->Array[Vector2i]:
	var diamond_cells: Array[Vector2i]
	for dx in range(-size, size + 1):
		var remaining = size - abs(dx)
		for dy in range(-size, remaining + 1):
			if abs(dx) + abs(dy) <= size:
				var new_cell = center_cell + Vector2i(dx, dy)
				if !diamond_cells.has(new_cell):
					diamond_cells.append(new_cell)
	return diamond_cells
## 获取中心一侧线形的地块
static func get_line_cells(center_cell:Vector2i,dir:Vector2i,length:int)->Array[Vector2i]:
	var line_cells:Array[Vector2i]
	for i in length:
		if !line_cells.has(center_cell):
			line_cells.append(center_cell)
		center_cell += dir
	return line_cells
##获取十字线地块
static func get_cross_cells(center_cell:Vector2i,length:int)->Array[Vector2i]:
	var cross_cells:Array[Vector2i] = [center_cell]
	for i in length:
		cross_cells.append(Vector2i.LEFT * i + center_cell)
		cross_cells.append(Vector2i.RIGHT * i + center_cell)
		cross_cells.append(Vector2i.UP * i + center_cell)
		cross_cells.append(Vector2i.DOWN * i + center_cell)
	return cross_cells
## 获取中心周围正方形的地块
static func get_square_cells(center_cell:Vector2i,size:int)->Array[Vector2i]:
	var square_cells :Array[Vector2i]
	for x in range(-size, size + 1):
		for y in range(-size, size + 1):
			var new_cell = center_cell + Vector2i(x,y)
			if !square_cells.has(new_cell):
				square_cells.append(new_cell)
	return square_cells
