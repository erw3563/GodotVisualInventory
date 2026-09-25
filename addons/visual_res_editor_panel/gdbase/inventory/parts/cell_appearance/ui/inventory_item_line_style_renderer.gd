@tool
class_name InventoryItemLineStyleRenderer
extends InventoryItemStyleRenderer
## 使用独占画布绘制填充与暴露边。
var inventory_grid_panel: InventoryGridPanel
var effective_width := 3.0

func _accept_style(value: InventoryItemVisualStyle) -> bool:
	return value is InventoryItemLineVisualStyle

func _render() -> void:
	inventory_grid_panel = context.grid
	var line_style := style as InventoryItemLineVisualStyle
	effective_width = line_style.border_width if line_style.border_width > 0.0 else context.default_border_width
	if not fill_cells.is_empty():
		var fill_canvas := Control.new()
		own_drawing(fill_canvas, context.fill_parent)
		fill_canvas.draw.connect(func(): _draw_cells_fill(fill_canvas, fill_cells, style.fill_color))
		fill_canvas.queue_redraw()
	if not border_cells.is_empty() and effective_width > 0.0:
		var border_canvas := Control.new()
		own_drawing(border_canvas, context.border_parent)
		border_canvas.draw.connect(func(): _draw_cells_border(border_canvas, border_cells, style.border_color, effective_width))
		border_canvas.queue_redraw()

func _draw_cells_fill(target_control: Control, target_cells: Array[Vector2i], fill_color: Color) -> void:
	if !is_instance_valid(inventory_grid_panel):
		return
	for target_cell in target_cells:
		var cell_position := inventory_grid_panel.get_cell_local_position(target_cell)
		var cell_rect := Rect2(cell_position, inventory_grid_panel.cell_size)
		target_control.draw_rect(cell_rect, fill_color, true)

## 绘制格集合的暴露边。
func _draw_cells_border(
	target_control: Control,
	target_cells: Array[Vector2i],
	border_color: Color,
	draw_border_width: float
) -> void:
	if !is_instance_valid(inventory_grid_panel):
		return
	var cell_lookup: Dictionary = {}
	for target_cell in target_cells:
		cell_lookup[target_cell] = true

	for target_cell in target_cells:
		var cell_position := inventory_grid_panel.get_cell_local_position(target_cell)
		var cell_size := inventory_grid_panel.cell_size
		var top_cell := target_cell + Vector2i(0, -1)
		var right_cell := target_cell + Vector2i(1, 0)
		var bottom_cell := target_cell + Vector2i(0, 1)
		var left_cell := target_cell + Vector2i(-1, 0)

		var top_left_point := cell_position
		var top_right_point := cell_position + Vector2(cell_size.x, 0.0)
		var bottom_left_point := cell_position + Vector2(0.0, cell_size.y)
		var bottom_right_point := cell_position + Vector2(cell_size.x, cell_size.y)

		if !_lookup_has_cell(cell_lookup, top_cell):
			target_control.draw_line(top_left_point, top_right_point, border_color, draw_border_width)
		if !_lookup_has_cell(cell_lookup, right_cell):
			target_control.draw_line(top_right_point, bottom_right_point, border_color, draw_border_width)
		if !_lookup_has_cell(cell_lookup, bottom_cell):
			target_control.draw_line(bottom_left_point, bottom_right_point, border_color, draw_border_width)
		if !_lookup_has_cell(cell_lookup, left_cell):
			target_control.draw_line(top_left_point, bottom_left_point, border_color, draw_border_width)

## 判断格子是否存在于查找表中。
func _lookup_has_cell(cell_lookup: Dictionary, cell_index: Vector2i) -> bool:
	return cell_lookup.has(cell_index)
