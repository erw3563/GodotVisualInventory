class_name QuickDrag
extends Node
## 使 [Control] 可被鼠标拖拽；支持自由、仅水平、仅竖直，并在后两种模式下可选限制在以「本次按下时控件 position」为基准的线段上。

signal drag_down(vec:Vector2)

enum DragMode {
	FREE,
	HORIZONTAL_ONLY,
	VERTICAL_ONLY,
}

## 被拖拽的控件；留空则当父节点为 [Control] 时将其作为目标。
@export var dragged_ui: Control
## 能够被鼠标点击以开始拖动的 Control 节点
@export var clickable_ui:Control
## 位置落笔中介（鸭子契约：实现 place(control, proposed, intent) 的节点，QuickUiAnimHost 即是）；
## 拖拽落笔以 INTERACTIVE 意图经其裁决加工，可打断演出租约。留空则直写（散装）。
@export var placer: Node
## 拖拽模式：自由、仅水平轴线段、仅竖直轴线段。
@export var drag_mode: DragMode = DragMode.FREE
## 是否自动接管 clickable_ui 的左键按压以开始拖拽；关闭后需自行调用 [method begin_drag]
@export var auto_to_process_click:bool = true
## 在仅水平 / 仅竖直模式下，是否将位移限制在对应轴上；区间相对本次拖拽开始时的控件 [member Control.position]（父节点本地空间）。
@export var use_axis_range_limit: bool = false
## 水平模式：相对拖拽起始 X 的偏移下限（可为负，例如 -50 表示最多向左 50px）。
@export var horizontal_range_min_offset: float = 0.0
## 水平模式：相对拖拽起始 X 的偏移上限（例如 120 表示最多向右 120px）。
@export var horizontal_range_max_offset: float = 0.0
## 竖直模式：相对拖拽起始 Y 的偏移下限。
@export var vertical_range_min_offset: float = 0.0
## 竖直模式：相对拖拽起始 Y 的偏移上限。
@export var vertical_range_max_offset: float = 0.0
@export_group("reset")
@export var is_reset_horizontal_max:bool = true
@export var is_reset_horizontal_min:bool = true
@export var is_reset_vertical_max:bool = true
@export var is_reset_vertical_min:bool = true
## 按下时鼠标与控件原点（全局）的偏移，用于保持抓取点不跳动。
var _grab_pos_offset: Vector2
## 开始拖拽时控件的位置
var _grab_start_pos:Vector2
## 拖拽上限
var horizontal_range_min:float
## 拖拽下限
var horizontal_range_max:float
## 拖拽左限
var vertical_range_min:float
## 拖拽右限
var vertical_range_max:float
## 是否正在拖拽
var is_draging:bool

func _ready() -> void:
	if dragged_ui == null:
		push_error("QuickDrag: 未设置 dragged_ui 无法拖拽。")
		return
	if auto_to_process_click and clickable_ui != null:
		clickable_ui.gui_input.connect(_on_clickable_gui_input)
	set_process_input(false)
	if use_axis_range_limit:
		await _reset_range()

## 按开关重采样轴向范围：等布局稳定后基于控件当前位置。
func _reset_range():
	await QuickUI.layout_settled(self)
	if is_reset_horizontal_max:
		horizontal_range_max = dragged_ui.global_position.x + horizontal_range_max_offset
	if is_reset_horizontal_min:
		horizontal_range_min = dragged_ui.global_position.x - horizontal_range_min_offset
	if is_reset_vertical_max:
		vertical_range_max = dragged_ui.global_position.y + vertical_range_max_offset
	if is_reset_vertical_min:
		vertical_range_min = dragged_ui.global_position.y - vertical_range_min_offset

func _move_range(vec:Vector2):
	await get_tree().process_frame
	horizontal_range_max += vec.x
	horizontal_range_min += vec.x
	vertical_range_max += vec.y
	vertical_range_min += vec.y

## clickable_ui 的 gui_input 回调：事件未被上层控件遮挡时才会到达。
func _on_clickable_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		clickable_ui.accept_event()
		begin_drag(clickable_ui.get_global_transform() * event.position)

## 开始拖拽：记录抓取偏移与起点。press_global 留空时回退真实鼠标位置
## （auto_to_process_click 关闭、手动调用时的路径）。
func begin_drag(press_global := Vector2.INF) -> void:
	if dragged_ui == null or is_draging:
		return
	var mouse_global := press_global
	if mouse_global == Vector2.INF:
		mouse_global = dragged_ui.get_global_mouse_position()
	_grab_pos_offset = dragged_ui.global_position - mouse_global
	_grab_start_pos = dragged_ui.global_position
	is_draging = true
	set_process_input(true)

## 拖拽期间监听全局鼠标：移动事件跟手更新位置，左键释放（含控件外）结束拖拽。
func _input(event: InputEvent) -> void:
	if is_draging and event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		get_viewport().set_input_as_handled()
		_end_drag()
	elif is_draging and event is InputEventMouseMotion:
		var new_pos: Vector2 = dragged_ui.get_canvas_transform().affine_inverse() * event.position
		new_pos += _grab_pos_offset
		# 先按自身模式约束（提议），再经中介以交互意图裁决加工后落笔。
		_place_proposed(_apply_drag_constraints(new_pos))

## 结束拖拽：停止释放/移动监听，发出位移信号。
func _end_drag() -> void:
	is_draging = false
	set_process_input(false)
	drag_down.emit(dragged_ui.global_position - _grab_start_pos)

## 拖拽落笔：经中介以交互意图加工（无中介时直写，语义等价于空管道）。
func _place_proposed(proposed: Vector2) -> void:
	if placer != null and placer.has_method("place"):
		placer.place(dragged_ui, proposed, QuickUI.PlaceIntent.INTERACTIVE)
	else:
		dragged_ui.global_position = proposed

## 按模式与可选区间限制父节点本地坐标。
func _apply_drag_constraints(position: Vector2) -> Vector2:
	var result := position
	match drag_mode:
		DragMode.FREE:
			if use_axis_range_limit:
				result.x = clampf(result.x, horizontal_range_min, horizontal_range_max)
				result.y = clampf(result.y, vertical_range_min, vertical_range_max)
		DragMode.HORIZONTAL_ONLY:
			result.y = _grab_start_pos.y
			if use_axis_range_limit:
				result.x = clampf(result.x, horizontal_range_min, horizontal_range_max)
		DragMode.VERTICAL_ONLY:
			result.x = _grab_start_pos.x
			if use_axis_range_limit:
				result.y = clampf(result.y, vertical_range_min, vertical_range_max)
	return result
