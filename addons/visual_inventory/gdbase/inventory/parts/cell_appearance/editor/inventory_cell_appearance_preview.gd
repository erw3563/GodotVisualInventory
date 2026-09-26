@tool
extends Control
## 当前外观键的隔离预览，复用覆盖层渲染策略。
var style: InventoryItemVisualStyle
var configuration: InventoryCellAppearanceFeatureDefinition
var grid: InventoryGridPanel
var canvas: Control
var renderer: InventoryItemStyleRenderer
var shape_index := 0
var light_background := false
var zoom := 1.0
var _queued := false
var editor_scale := 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	editor_scale = EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
	custom_minimum_size.y = 180 * editor_scale
	grid = InventoryGridPanel.new()
	grid.cell_size = Vector2(48, 48) * editor_scale
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	grid.visible = false
	add_child(grid)
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	resized.connect(_center_canvas)
	refresh()

func set_style(value: InventoryItemVisualStyle, config: InventoryCellAppearanceFeatureDefinition = null) -> void:
	style = value
	configuration = config
	request_refresh()

func request_refresh() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	refresh.call_deferred()

func cells() -> Array[Vector2i]:
	if shape_index == 1:
		return [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]
	if shape_index == 2:
		return [Vector2i.ZERO, Vector2i(0, 1), Vector2i(1, 1)]
	return [Vector2i.ZERO]

func refresh() -> void:
	_queued = false
	if not is_instance_valid(canvas):
		return
	_release_renderer()
	if style != null and style.validate_configuration().is_empty():
		var binding := InventoryItemStyleRenderContext.new()
		binding.grid = grid
		binding.default_border_width = configuration.border_width if configuration != null else 3.0
		binding.fill_parent = canvas
		binding.border_parent = canvas
		renderer = style.create_renderer()
		if renderer != null:
			add_child(renderer)
			if renderer.configure(style, binding):
				renderer.render(cells(), cells())
			else:
				_release_renderer()
	canvas.scale = Vector2.ONE * zoom
	custom_minimum_size.y = maxf(180, 72 + (48 if shape_index == 0 else 96) * zoom) * editor_scale
	_center_canvas()
	canvas.queue_redraw()
	queue_redraw()

func _center_canvas() -> void:
	var shape_cells := cells()
	var bounds := Rect2(grid.get_cell_local_position(shape_cells[0]), grid.cell_size)
	for cell in shape_cells:
		bounds = bounds.merge(Rect2(grid.get_cell_local_position(cell), grid.cell_size))
	canvas.position = size * 0.5 - bounds.get_center() * zoom

func _draw() -> void:
	var base := Color(0.8, 0.8, 0.8) if light_background else Color(0.12, 0.12, 0.12)
	draw_rect(Rect2(Vector2.ZERO, size), base)
	for y in range(0, ceili(size.y), 12):
		for x in range(0, ceili(size.x), 12):
			if (x / 12 + y / 12) % 2 == 0:
				draw_rect(Rect2(Vector2(x, y), Vector2(12, 12)), base.lightened(0.09))

func _release_renderer() -> void:
	if is_instance_valid(renderer):
		renderer.release()
		remove_child(renderer)
		renderer.queue_free()
	renderer = null

func _exit_tree() -> void:
	_release_renderer()
