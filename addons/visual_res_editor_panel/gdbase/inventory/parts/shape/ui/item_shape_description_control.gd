@tool
class_name ItemShapeDescriptionControl
extends Control
## 形状描述的纯网格预览。持有坐标副本，不修改模板或实例轮廓。

const CELL_SIZE := 12.0
const CELL_GAP := 2.0
const MAX_PREVIEW_SIZE := 96.0
const FILLED_COLOR := Color(0.68, 0.80, 0.94, 1.0)
const EMPTY_COLOR := Color(0.55, 0.65, 0.78, 0.10)
const BORDER_COLOR := Color(0.85, 0.91, 1.0, 0.85)

var _cells: Array[Vector2i] = [Vector2i.ZERO]
var _bounds := Rect2i(Vector2i.ZERO, Vector2i.ONE)


static func create(local_cells: Array[Vector2i], direction: Vector2 = Vector2.RIGHT) -> ItemShapeDescriptionControl:
	var control := ItemShapeDescriptionControl.new()
	control.set_shape_cells(local_cells, direction)
	return control


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func set_shape_cells(local_cells: Array[Vector2i], direction: Vector2 = Vector2.RIGHT) -> void:
	var source_cells: Array[Vector2i] = local_cells
	if source_cells.is_empty():
		source_cells = [Vector2i.ZERO]
	_cells = ShapeTransform.rotate_cells_by_dir(source_cells, direction)
	_bounds = ShapeTransform.bounding_rect(_cells)
	update_minimum_size()
	queue_redraw()


func get_display_cells() -> Array[Vector2i]:
	return _cells.duplicate()


func get_grid_bounds() -> Rect2i:
	return _bounds


func get_preview_size() -> Vector2:
	var natural_size := Vector2(_bounds.size) * (CELL_SIZE + CELL_GAP) - Vector2.ONE * CELL_GAP
	return natural_size * minf(1.0, MAX_PREVIEW_SIZE / maxf(natural_size.x, natural_size.y))


func _get_minimum_size() -> Vector2:
	return get_preview_size()


func _draw() -> void:
	var preview_size := get_preview_size()
	var natural_size := Vector2(_bounds.size) * (CELL_SIZE + CELL_GAP) - Vector2.ONE * CELL_GAP
	var scale_factor := preview_size.x / natural_size.x
	var origin := (size - preview_size) * 0.5
	var occupied := {}
	for cell in _cells:
		occupied[cell] = true
	for y in range(_bounds.size.y):
		for x in range(_bounds.size.x):
			var cell := Vector2i(x, y) + _bounds.position
			var rect := Rect2(origin + Vector2(x, y) * (CELL_SIZE + CELL_GAP) * scale_factor,
				Vector2.ONE * CELL_SIZE * scale_factor)
			draw_rect(rect, FILLED_COLOR if occupied.has(cell) else EMPTY_COLOR)
			if occupied.has(cell):
				var border_width := minf(1.0, scale_factor)
				draw_rect(rect.grow(-border_width * 0.5), BORDER_COLOR, false, border_width)
