@tool
extends Control

## PathDefinition 曲线编辑视图：左键命中控制点则拖动、命中曲线则在该处加点、
## 点击空白处新建短曲线；右键命中激活曲线控制点则删除（删尽移除曲线）、
## 命中其它曲线则切换为激活曲线。
## 曲线点的原地修改经 paths_edited 提交；增删整条曲线与切换经请求信号交回面板执行。

signal paths_edited
signal create_curve_requested(world_position: Vector2)
signal remove_curve_requested
signal select_curve_requested(curve_index: int)
signal view_changed
signal pointer_changed(position: Vector2)

const POINT_PICK_RADIUS := 10.0
const LINE_HIT_RADIUS := 10.0
const DEFAULT_BOUNDS := Rect2(-100, -100, 200, 200)
const GRID_COLOR := Color(1, 1, 1, 0.06)
const AXIS_COLOR := Color(1, 1, 1, 0.2)
const CURVE_COLOR := Color(0.55, 0.55, 0.6)
const ACTIVE_CURVE_COLOR := Color(0.3, 0.7, 1.0)
const POINT_COLOR := Color.WHITE
const POINT_RADIUS := 4.0
const HOVERED_POINT_COLOR := Color(1.0, 0.85, 0.3)
const HOVERED_POINT_RADIUS := 5.5

## 当前编辑的路径配置资源与激活曲线，由面板同步。
var definition: PathDefinition
var active_curve_index := 0

var _bounds_fitted := false
var _drag_point_index := -1
var _hovered_point_index := -1
var view_center := Vector2.ZERO
var zoom := 1.0
var reference_rect := Rect2(0, 0, 64, 64)
var reference_visible := true
var _panning := false

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if not _bounds_fitted and definition != null:
			fit_all()
		queue_redraw()
		view_changed.emit()

## 首次绑定／换绑资源适配；普通编辑、增删点和窗口尺寸变化保持中心与缩放。
func refresh(force_fit := false) -> void:
	if _drag_point_index < 0:
		_apply_bounds_update(force_fit)
	queue_redraw()

func _get_scale() -> float:
	return zoom

func world_to_view(world: Vector2) -> Vector2:
	return (world - view_center) * zoom + size * 0.5

func view_to_world(view: Vector2) -> Vector2:
	return (view - size * 0.5) / zoom + view_center

func set_view(center: Vector2, new_zoom: float) -> void:
	view_center = center
	zoom = clampf(new_zoom, 0.01, 100.0)
	_bounds_fitted = true
	queue_redraw()
	view_changed.emit()

func zoom_at(view_position: Vector2, factor: float) -> void:
	var anchor := view_to_world(view_position)
	var next_zoom := clampf(zoom * factor, 0.01, 100.0)
	set_view(anchor - (view_position - size * 0.5) / next_zoom, next_zoom)

func pan_by(delta: Vector2) -> void:
	set_view(view_center - delta / zoom, zoom)

func set_visible_width(width: float) -> void:
	set_view(view_center, maxf(size.x, 1.0) / maxf(width, 0.01))

func fit_all() -> void:
	_fit_rect(_compute_content_bounds())

func fit_active() -> void:
	var curve := _get_active_curve()
	if curve == null or curve.point_count == 0:
		return
	var bounds := Rect2(curve.get_point_position(0), Vector2.ZERO)
	for point in curve.get_baked_points():
		bounds = bounds.expand(point)
	_fit_rect(bounds)

func reset_origin() -> void:
	set_view(Vector2.ZERO, zoom)

func _fit_rect(rect: Rect2) -> void:
	if size.x < 1.0 or size.y < 1.0:
		_bounds_fitted = false
		return
	var extent := rect.size.max(Vector2.ONE)
	set_view(rect.get_center(), minf(maxf(size.x - 48.0, 1.0) / extent.x, maxf(size.y - 48.0, 1.0) / extent.y))

func set_reference(rect: Rect2, enabled: bool) -> void:
	reference_rect = Rect2(rect.position, rect.size.max(Vector2.ONE))
	reference_visible = enabled
	queue_redraw()

func _draw() -> void:
	_draw_grid()
	if reference_visible:
		var rect := Rect2(world_to_view(reference_rect.position), reference_rect.size * zoom)
		draw_rect(rect, Color(0.8, 0.7, 0.3, 0.65), false, 1.0)
	if definition == null:
		return
	for curve_index in definition.paths.size():
		var curve := definition.paths[curve_index]
		if curve == null or curve.point_count < 2:
			continue
		var is_active := curve_index == active_curve_index
		var points := PackedVector2Array()
		for baked_point in curve.get_baked_points():
			points.append(world_to_view(baked_point))
		draw_polyline(points, ACTIVE_CURVE_COLOR if is_active else CURVE_COLOR, 2.0)

	var active_curve := _get_active_curve()
	if active_curve == null:
		return
	for point_index in active_curve.point_count:
		var position := active_curve.get_point_position(point_index)
		var is_hovered := point_index == _hovered_point_index or point_index == _drag_point_index
		draw_circle(
			world_to_view(position),
			HOVERED_POINT_RADIUS if is_hovered else POINT_RADIUS,
			HOVERED_POINT_COLOR if is_hovered else POINT_COLOR
		)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			accept_event()
			return
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_at(event.position, 1.2 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.2)
			accept_event()
			return
	if event is InputEventMouseMotion:
		pointer_changed.emit(view_to_world(event.position))
		if _panning and (event.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0:
			pan_by(event.relative)
			accept_event()
			return
		_panning = false
	if definition == null:
		return
	var world := view_to_world(get_local_mouse_position())

	if event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		if button_event.button_index == MOUSE_BUTTON_LEFT:
			if button_event.pressed:
				apply_left_press_at(world)
			else:
				end_drag()
			queue_redraw()
			return
		if button_event.button_index == MOUSE_BUTTON_RIGHT and button_event.pressed:
			apply_right_press_at(world)
			queue_redraw()
			return

	if event is InputEventMouseMotion:
		_hovered_point_index = _find_point_index_near(world)
		if _drag_point_index >= 0:
			drag_to(world)
		_update_hover_cursor(world)
		queue_redraw()

## 左键：优先抓取命中的控制点进入拖动，其次命中曲线（或不足两点的曲线）时加点，
## 最后点击空白处（不邻近任何曲线）请求新建短曲线。
func apply_left_press_at(world: Vector2) -> void:
	var curve := _get_active_curve()
	var point_index := -1
	if curve != null:
		point_index = _find_point_index_near(world)
	if point_index >= 0:
		_drag_point_index = point_index
		return
	if curve != null and (curve.point_count < 2 or _is_near_curve(curve, world)):
		_add_point_at(world)
		return
	if not _is_near_any_curve(world):
		create_curve_requested.emit(world)

## 右键：命中激活曲线控制点则删除（删尽移除曲线）；命中其它曲线则切换为激活曲线。
func apply_right_press_at(world: Vector2) -> void:
	var curve := _get_active_curve()
	if curve != null and _find_point_index_near(world) >= 0:
		_delete_point_near(world)
		return
	var curve_index := _find_other_curve_index_at(world)
	if curve_index >= 0:
		select_curve_requested.emit(curve_index)

## 命中除激活曲线外的哪条曲线（线体命中带宽或控制点拾取半径内）；未命中返回 -1。
func _find_other_curve_index_at(world: Vector2) -> int:
	if definition == null:
		return -1
	var line_threshold := LINE_HIT_RADIUS / maxf(_get_scale(), 0.0001)
	var point_radius := POINT_PICK_RADIUS / maxf(_get_scale(), 0.0001)
	for curve_index in definition.paths.size():
		if curve_index == active_curve_index:
			continue
		var curve := definition.paths[curve_index]
		if curve == null:
			continue
		for point_index in curve.point_count:
			if curve.get_point_position(point_index).distance_to(world) <= point_radius:
				return curve_index
		var baked := curve.get_baked_points()
		for baked_index in baked.size() - 1:
			if _distance_to_segment(world, baked[baked_index], baked[baked_index + 1]) <= line_threshold:
				return curve_index
	return -1

## 结束拖拽，保持用户视图。
func end_drag() -> void:
	if _drag_point_index < 0:
		return
	_drag_point_index = -1
	_apply_bounds_update()
	queue_redraw()

## 拖拽中移动当前抓取的点。
func drag_to(world: Vector2) -> void:
	var curve := _get_active_curve()
	if curve == null or _drag_point_index < 0 or _drag_point_index >= curve.point_count:
		return
	curve.set_point_position(_drag_point_index, world)
	paths_edited.emit()
	queue_redraw()

func _get_active_curve() -> Curve2D:
	if definition == null or active_curve_index < 0 or active_curve_index >= definition.paths.size():
		return null
	return definition.paths[active_curve_index]

func _add_point_at(world: Vector2) -> void:
	var curve := _get_active_curve()
	if curve == null:
		return
	if curve.point_count < 2:
		curve.add_point(world)
	else:
		curve.add_point(world, Vector2.ZERO, Vector2.ZERO, _nearest_segment_index(curve, world) + 1)
	paths_edited.emit()
	_apply_bounds_update()
	queue_redraw()

func _delete_point_near(world: Vector2) -> void:
	var curve := _get_active_curve()
	if curve == null:
		return
	var index := _find_point_index_near(world)
	if index < 0:
		return
	if curve.point_count > 1:
		curve.remove_point(index)
		paths_edited.emit()
		_apply_bounds_update()
		queue_redraw()
	else:
		remove_curve_requested.emit()

func _find_point_index_near(world: Vector2) -> int:
	var curve := _get_active_curve()
	if curve == null:
		return -1
	var radius_world := POINT_PICK_RADIUS / maxf(_get_scale(), 0.0001)
	var best_index := -1
	var best_distance := radius_world
	for index in curve.point_count:
		var distance := curve.get_point_position(index).distance_to(world)
		if distance <= best_distance:
			best_distance = distance
			best_index = index
	return best_index

## 点击是否落在烘焙曲线的命中带宽内；不足两点的曲线视为处处命中便于从头加点。
func _is_near_curve(curve: Curve2D, world: Vector2) -> bool:
	var baked := curve.get_baked_points()
	if baked.size() < 2:
		return true
	var threshold := LINE_HIT_RADIUS / maxf(_get_scale(), 0.0001)
	for index in baked.size() - 1:
		if _distance_to_segment(world, baked[index], baked[index + 1]) <= threshold:
			return true
	return false

## 是否邻近任意一条可建曲线（两点及以上）的线体；单点／空曲线不可见，不遮挡空白判断。
func _is_near_any_curve(world: Vector2) -> bool:
	if definition == null:
		return false
	for curve in definition.paths:
		if curve == null or curve.point_count < 2:
			continue
		if _is_near_curve(curve, world):
			return true
	return false

func _distance_to_segment(point: Vector2, from: Vector2, to: Vector2) -> float:
	var direction := to - from
	var t := 0.0
	if direction.length_squared() > 0.0000001:
		t = clampf((point - from).dot(direction) / direction.length_squared(), 0.0, 1.0)
	return point.distance_to(from + direction * t)

## 返回距离世界坐标最近的相邻控制点线段索引，插入位置为其后。
func _nearest_segment_index(curve: Curve2D, world: Vector2) -> int:
	var best_index := 0
	var best_distance := INF
	for index in curve.point_count - 1:
		var distance := _distance_to_segment(
			world, curve.get_point_position(index), curve.get_point_position(index + 1)
		)
		if distance < best_distance:
			best_distance = distance
			best_index = index
	return best_index

func _update_hover_cursor(world: Vector2) -> void:
	if _hovered_point_index >= 0:
		set_default_cursor_shape(CURSOR_MOVE)
		return
	var curve := _get_active_curve()
	if curve != null and curve.point_count >= 2 and _is_near_curve(curve, world):
		set_default_cursor_shape(CURSOR_POINTING_HAND)
		return
	set_default_cursor_shape(CURSOR_ARROW)

func _apply_bounds_update(force_fit := false) -> void:
	if force_fit or not _bounds_fitted:
		fit_all()

## 全部控制点的紧包围盒；无任何点时返回默认范围。
func _compute_content_bounds() -> Rect2:
	if definition == null:
		return DEFAULT_BOUNDS
	var found := false
	var min_position := Vector2.ZERO
	var max_position := Vector2.ZERO
	for curve in definition.paths:
		if curve == null:
			continue
		var points := curve.get_baked_points()
		if points.is_empty() and curve.point_count > 0:
			points.append(curve.get_point_position(0))
		for point in points:
			if not found:
				min_position = point
				max_position = point
				found = true
			else:
				min_position = min_position.min(point)
				max_position = max_position.max(point)
	if not found:
		return DEFAULT_BOUNDS
	return Rect2(min_position, max_position - min_position)

func _draw_grid() -> void:
	var scale := _get_scale()
	if scale <= 0.0:
		return
	var start := view_to_world(Vector2.ZERO)
	var end := view_to_world(size)
	var step_world := pow(10.0, floorf(log(70.0 / scale) / log(10.0)))
	if step_world * scale < 35.0:
		step_world *= 5.0
	var font := get_theme_default_font()
	var line_index := floori(start.x / step_world)
	while true:
		var x := line_index * step_world
		if x > end.x:
			break
		var x_view := world_to_view(Vector2(x, 0)).x
		draw_line(Vector2(x_view, 0), Vector2(x_view, size.y), GRID_COLOR)
		draw_line(Vector2(x_view, 0), Vector2(x_view, 6), AXIS_COLOR)
		draw_string(font, Vector2(x_view + 2, 15), str(snappedf(x, 0.0001)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.7, 0.7))
		line_index += 1
	line_index = floori(start.y / step_world)
	while true:
		var y := line_index * step_world
		if y > end.y:
			break
		var y_view := world_to_view(Vector2(0, y)).y
		draw_line(Vector2(0, y_view), Vector2(size.x, y_view), GRID_COLOR)
		draw_line(Vector2(0, y_view), Vector2(6, y_view), AXIS_COLOR)
		draw_string(font, Vector2(2, y_view - 2), str(snappedf(y, 0.0001)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.7, 0.7, 0.7))
		line_index += 1
	if Rect2(start, end - start).has_point(Vector2.ZERO):
		var origin_x := world_to_view(Vector2.ZERO).x
		var origin_y := world_to_view(Vector2.ZERO).y
		draw_line(Vector2(origin_x, 0), Vector2(origin_x, size.y), AXIS_COLOR)
		draw_line(Vector2(0, origin_y), Vector2(size.x, origin_y), AXIS_COLOR)
