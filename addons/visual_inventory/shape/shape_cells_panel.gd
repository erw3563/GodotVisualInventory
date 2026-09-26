@tool
extends PanelContainer

## 当面板中的坐标按钮被切换时发出。
## shape_cells_property_editor.gd 会监听这个信号，并把新数组写回 Shape.cells。
signal cells_changed(new_cells: Array[Vector2i])
## 请求在独立弹窗中打开可视化面板。
signal popup_requested

## 坐标面板以 (0, 0) 为中心向四个方向展开。
## 半径为 4 时，实际显示范围是 x: -4 到 4，y: -4 到 4。
const DEFAULT_AXIS_RADIUS := 2
const MIN_AXIS_RADIUS := 1
const MAX_AXIS_RADIUS := 12
const BUTTON_MINIMUM_SIZE := Vector2(48, 48)
const SELECTED_BUTTON_MODULATE := Color(1.6, 1.6, 1.6)
const NORMAL_BUTTON_MODULATE := Color.WHITE
const BOX_SELECT_DRAG_THRESHOLD := 4.0
const INVALID_CELL := Vector2i(2147483647, 2147483647)

enum BoxSelectMode {
	ADD,
	REMOVE,
}

## 场景中预留的容器和范围调整按钮。
## GridContainer 只负责排列按钮，具体坐标由 button_by_cell 字典记录。
@onready var grid_container: GridContainer = $MarginContainer/HBoxContainer2/HBoxContainer/ScrollContainer/GridContainer
@onready var scroll_container: ScrollContainer = $MarginContainer/HBoxContainer2/HBoxContainer/ScrollContainer
@onready var x_decrease_button: Button = $MarginContainer/HBoxContainer2/HBoxContainer2/XSubButton
@onready var x_increase_button: Button = $MarginContainer/HBoxContainer2/HBoxContainer2/XAddButton
@onready var y_decrease_button: Button = $MarginContainer/HBoxContainer2/HBoxContainer/VBoxContainer/YSubButton
@onready var y_increase_button: Button = $MarginContainer/HBoxContainer2/HBoxContainer/VBoxContainer/YAddButton
@onready var pop_button: Button = $MarginContainer/HBoxContainer2/HBoxContainer2/PopButton

## 当前面板绑定的 Shape 资源，由属性编辑器传入。
var shape_resource: Shape
## 当前已选中的坐标集合。这里是面板缓存，真正写回由 cells_changed 信号完成。
var cells: Array[Vector2i] = []
## 坐标到按钮节点的映射，用来刷新按钮选中状态。
var button_by_cell: Dictionary = {}
var status_label: Label
## 当前可见坐标范围的横向和纵向半径。
var x_radius := DEFAULT_AXIS_RADIUS
var y_radius := DEFAULT_AXIS_RADIUS
var box_selection_overlay: BoxSelectionOverlay
var is_pending_click := false
var is_box_select_active := false
var box_select_start_global := Vector2.ZERO
var box_select_end_global := Vector2.ZERO
var box_select_mode := BoxSelectMode.ADD
var active_mouse_button := MOUSE_BUTTON_NONE

func _ready() -> void:
	_connect_resize_buttons()
	_connect_pop_button()
	_setup_box_selection()
	_build_layout()
	_refresh_buttons()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button_event := event as InputEventMouseButton
		if mouse_button_event.pressed:
			if !is_pending_click and !is_box_select_active and _try_begin_mouse_interaction(mouse_button_event):
				get_viewport().set_input_as_handled()
			return

		if (is_pending_click or is_box_select_active) and mouse_button_event.button_index == active_mouse_button:
			_finish_mouse_interaction(mouse_button_event.global_position)
			get_viewport().set_input_as_handled()
		return

	if !is_pending_click and !is_box_select_active:
		return

	if event is InputEventMouseMotion:
		var motion_event := event as InputEventMouseMotion
		if is_pending_click:
			if box_select_start_global.distance_to(motion_event.global_position) >= BOX_SELECT_DRAG_THRESHOLD:
				_start_box_select(motion_event.global_position)
		if is_box_select_active:
			box_select_end_global = motion_event.global_position
			_update_box_selection_visual(box_select_mode)
		get_viewport().set_input_as_handled()

## 绑定当前正在编辑的 Shape 资源。
func set_shape_resource(new_shape_resource: Shape) -> void:
	shape_resource = new_shape_resource

## 从检查器同步 cells 数据到可视化按钮状态。
func set_cells(new_cells: Array[Vector2i]) -> void:
	cells = _get_unique_cells(new_cells)
	_refresh_buttons()

## 根据当前 x_radius 和 y_radius 重新生成坐标按钮。
## 重新生成只影响可见按钮，不会修改 cells 中已经保存的坐标数据。
func _build_layout() -> void:
	for child in grid_container.get_children():
		grid_container.remove_child(child)
		child.queue_free()
	button_by_cell.clear()

	# GridContainer 按列数自动换行，所以列数必须等于横向格子数量。
	grid_container.columns = x_radius * 2 + 1
	for cell_y in range(-y_radius, y_radius + 1):
		for cell_x in range(-x_radius, x_radius + 1):
			var cell := Vector2i(cell_x, cell_y)
			var cell_button := Button.new()
			cell_button.custom_minimum_size = BUTTON_MINIMUM_SIZE
			cell_button.focus_mode = Control.FOCUS_NONE
			cell_button.toggle_mode = true
			cell_button.tooltip_text = "(%d, %d)" % [cell.x, cell.y]
			button_by_cell[cell] = cell_button
			grid_container.add_child(cell_button)
	_update_selection_overlay_size()
	_refresh_resize_buttons()

## 取消单个格子选中状态。
func _deselect_cell(cell: Vector2i) -> void:
	if !cells.has(cell):
		return

	cells.erase(cell)
	cells_changed.emit(cells.duplicate())
	_refresh_buttons()


## 切换单个格子选中状态。
func _toggle_cell(cell: Vector2i) -> void:
	if cells.has(cell):
		cells.erase(cell)
	else:
		cells.append(cell)

	cells_changed.emit(cells.duplicate())
	_refresh_buttons()


## 调整可见坐标按钮范围，不直接修改 Shape.cells 数据。
## axis 决定修改横向还是纵向半径，amount 决定增加或减少。
func _change_grid_axis_radius(axis: Vector2i, amount: int) -> void:
	x_radius = clampi(x_radius + axis.x * amount, MIN_AXIS_RADIUS, MAX_AXIS_RADIUS)
	y_radius = clampi(y_radius + axis.y * amount, MIN_AXIS_RADIUS, MAX_AXIS_RADIUS)
	_build_layout()
	_refresh_buttons()

## 按照 cells 缓存刷新所有可见按钮的选中状态。
## 如果 cells 中存在当前不可见的坐标，它们会保留在数组中，等范围扩大后再显示。
func _refresh_buttons() -> void:
	if status_label != null:
		status_label.text = "cells: %d" % cells.size()

	for cell in button_by_cell:
		var cell_button := button_by_cell[cell] as Button
		var is_selected := cells.has(cell)
		cell_button.button_pressed = is_selected
		cell_button.modulate = SELECTED_BUTTON_MODULATE if is_selected else NORMAL_BUTTON_MODULATE
	_refresh_resize_buttons()

## 初始化框选 overlay。
func _setup_box_selection() -> void:
	box_selection_overlay = BoxSelectionOverlay.new()
	box_selection_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box_selection_overlay.z_index = 1
	scroll_container.add_child(box_selection_overlay)


## 在网格区域按下鼠标时，准备单击或框选。
func _try_begin_mouse_interaction(event: InputEventMouseButton) -> bool:
	if !_is_global_point_in_grid_area(event.global_position):
		return false

	if event.button_index == MOUSE_BUTTON_LEFT:
		_begin_mouse_interaction(event.global_position, MOUSE_BUTTON_LEFT, BoxSelectMode.ADD)
		return true
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_begin_mouse_interaction(event.global_position, MOUSE_BUTTON_RIGHT, BoxSelectMode.REMOVE)
		return true

	return false


## 记录鼠标按下位置，等待判断是单击还是框选。
func _begin_mouse_interaction(
	global_position: Vector2,
	mouse_button: int,
	select_mode: BoxSelectMode
) -> void:
	is_pending_click = true
	is_box_select_active = false
	active_mouse_button = mouse_button
	box_select_mode = select_mode
	box_select_start_global = global_position
	box_select_end_global = global_position
	_clear_box_selection_visual()


## 拖拽超过阈值后进入框选模式。
func _start_box_select(global_position: Vector2) -> void:
	is_pending_click = false
	is_box_select_active = true
	box_select_end_global = global_position
	_update_box_selection_visual(box_select_mode)


## 鼠标释放时执行单击或框选批量操作。
func _finish_mouse_interaction(release_global_position: Vector2) -> void:
	if is_box_select_active:
		box_select_end_global = release_global_position
		_apply_box_selection(box_select_mode)
	elif is_pending_click:
		var clicked_cell := _get_cell_at_global_position(box_select_start_global)
		if clicked_cell != INVALID_CELL:
			if box_select_mode == BoxSelectMode.ADD:
				_toggle_cell(clicked_cell)
			else:
				_deselect_cell(clicked_cell)

	is_pending_click = false
	is_box_select_active = false
	active_mouse_button = MOUSE_BUTTON_NONE
	_clear_box_selection_visual()


## 将框选矩形内的格子批量设为选中或取消选中。
func _apply_box_selection(select_mode: BoxSelectMode) -> void:
	var selection_rect := _get_selection_rect_global()
	var changed := false

	for cell in button_by_cell:
		var cell_button := button_by_cell[cell] as Control
		if !selection_rect.intersects(cell_button.get_global_rect()):
			continue

		if select_mode == BoxSelectMode.ADD:
			if cells.has(cell):
				continue
			cells.append(cell)
			changed = true
		else:
			if !cells.has(cell):
				continue
			cells.erase(cell)
			changed = true

	if changed:
		cells_changed.emit(cells.duplicate())

	_refresh_buttons()


## 判断鼠标是否位于网格编辑区域内。
func _is_global_point_in_grid_area(global_position: Vector2) -> bool:
	return grid_container.get_global_rect().has_point(global_position)


## 根据鼠标位置查找对应格子坐标。
func _get_cell_at_global_position(global_position: Vector2) -> Vector2i:
	for cell in button_by_cell:
		var cell_button := button_by_cell[cell] as Control
		if cell_button.get_global_rect().has_point(global_position):
			return cell

	return INVALID_CELL


## 获取框选矩形（全局坐标，宽高始终为正）。
func _get_selection_rect_global() -> Rect2:
	return _build_rect_from_two_points(box_select_start_global, box_select_end_global)


## 根据对角两点生成宽高为正的矩形。
func _build_rect_from_two_points(point_a: Vector2, point_b: Vector2) -> Rect2:
	var min_x := minf(point_a.x, point_b.x)
	var min_y := minf(point_a.y, point_b.y)
	var max_x := maxf(point_a.x, point_b.x)
	var max_y := maxf(point_a.y, point_b.y)
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))


## 更新框选 overlay 的位置与绘制区域。
func _update_box_selection_visual(select_mode: BoxSelectMode) -> void:
	if box_selection_overlay == null:
		return

	var overlay_origin := box_selection_overlay.get_global_rect().position
	var local_start := box_select_start_global - overlay_origin
	var local_end := box_select_end_global - overlay_origin
	box_selection_overlay.selection_rect = _build_rect_from_two_points(local_start, local_end)
	box_selection_overlay.select_mode = select_mode
	box_selection_overlay.is_showing_selection = true
	box_selection_overlay.queue_redraw()


## 清除框选 overlay 显示。
func _clear_box_selection_visual() -> void:
	if box_selection_overlay == null:
		return

	box_selection_overlay.is_showing_selection = false
	box_selection_overlay.selection_rect = Rect2()
	box_selection_overlay.queue_redraw()


## 让框选 overlay 与 GridContainer 尺寸对齐。
func _update_selection_overlay_size() -> void:
	if box_selection_overlay == null:
		return

	box_selection_overlay.position = grid_container.position
	box_selection_overlay.size = grid_container.size
	scroll_container.move_child(box_selection_overlay, -1)


## 连接弹出按钮。
func _connect_pop_button() -> void:
	if pop_button == null:
		return
	if pop_button.pressed.is_connected(_on_pop_button_pressed):
		return

	pop_button.pressed.connect(_on_pop_button_pressed)


## 请求在外部弹窗中打开当前面板。
func _on_pop_button_pressed() -> void:
	popup_requested.emit()


## 连接四个范围调整按钮。
## 这里使用 Vector2i.RIGHT 和 Vector2i.DOWN 只是为了表示“改 x 半径”或“改 y 半径”。
func _connect_resize_buttons() -> void:
	if x_decrease_button == null or x_increase_button == null or y_decrease_button == null or y_increase_button == null:
		return

	x_decrease_button.pressed.connect(_change_grid_axis_radius.bind(Vector2i.RIGHT, -1))
	x_increase_button.pressed.connect(_change_grid_axis_radius.bind(Vector2i.RIGHT, 1))
	y_decrease_button.pressed.connect(_change_grid_axis_radius.bind(Vector2i.DOWN, -1))
	y_increase_button.pressed.connect(_change_grid_axis_radius.bind(Vector2i.DOWN, 1))

## 在半径到达上下限时禁用对应按钮，避免无效点击。
func _refresh_resize_buttons() -> void:
	if x_decrease_button == null or x_increase_button == null or y_decrease_button == null or y_increase_button == null:
		return

	x_decrease_button.disabled = x_radius <= MIN_AXIS_RADIUS
	x_increase_button.disabled = x_radius >= MAX_AXIS_RADIUS
	y_decrease_button.disabled = y_radius <= MIN_AXIS_RADIUS
	y_increase_button.disabled = y_radius >= MAX_AXIS_RADIUS

## 保证 cells 中不会出现重复坐标，避免按钮状态和资源数据不一致。
func _get_unique_cells(input_cells: Array[Vector2i]) -> Array[Vector2i]:
	var unique_cells: Array[Vector2i] = []
	for cell in input_cells:
		if !unique_cells.has(cell):
			unique_cells.append(cell)
	return unique_cells


## 框选区域绘制层。
class BoxSelectionOverlay extends Control:
	const ADD_FILL_COLOR := Color(0.3, 0.6, 1.0, 0.25)
	const ADD_BORDER_COLOR := Color(0.3, 0.6, 1.0, 0.9)
	const REMOVE_FILL_COLOR := Color(1.0, 0.35, 0.35, 0.25)
	const REMOVE_BORDER_COLOR := Color(1.0, 0.35, 0.35, 0.9)

	var selection_rect := Rect2()
	var is_showing_selection := false
	var select_mode := BoxSelectMode.ADD

	func _draw() -> void:
		if !is_showing_selection or selection_rect.size == Vector2.ZERO:
			return

		var fill_color := ADD_FILL_COLOR if select_mode == BoxSelectMode.ADD else REMOVE_FILL_COLOR
		var border_color := ADD_BORDER_COLOR if select_mode == BoxSelectMode.ADD else REMOVE_BORDER_COLOR
		draw_rect(selection_rect, fill_color)
		draw_rect(selection_rect, border_color, false, 1.0)
