class_name QuickConstraints
extends Node
## 位置钳制 stage：宿主 [class QuickUiAnimHost] 落笔管道的加工者，按标记控件边界与
## 视口偏移把提议钳回合法驻留区域（apply_place 契约：只改提议、不落笔）。
## continuous 回收以 PLACEMENT 意图经宿主中介重钳，演出租约期间被意图表自动挂起。

@export var ui: Control
## 开启后每帧把 ui 重新钳回合法区域（应对窗口尺寸变化等外部搬运）；
## 关闭时只在宿主管道加工落笔提议时钳制。
@export var continuous: bool = false:
	set(value):
		continuous = value
		_update_process()
@export var is_opposite_constraints: bool
@export var is_froce_in_viewports: bool
@export_group("mark_control")
@export var mark_max_x_control: Control
@export var mark_max_x_offset: float
@export var mark_min_x_control: Control
@export var mark_min_x_offset: float
@export var mark_max_y_control: Control
@export var mark_max_y_offset: float
@export var mark_min_y_control: Control
@export var mark_min_y_offset: float
@export_group("viewprots")
@export var viewports_max_x_offset: float
@export var viewports_min_x_offset: float
@export var viewports_max_y_offset: float
@export var viewports_min_y_offset: float

func _ready() -> void:
	_update_process()

## 持续钳制按需参与帧循环，默认关闭时零开销。
func _update_process() -> void:
	set_process(continuous and is_inside_tree())

func _process(_delta: float) -> void:
	if ui == null:
		return
	# 经宿主中介以 PLACEMENT 意图重钳：演出租约期间被自动挂起；
	# 父节点未实现 place 契约（散装摆放）时退化为直接钳制写回。
	var p := get_parent()
	if p != null and p.has_method("place"):
		p.place(ui, ui.global_position, QuickUI.PlaceIntent.PLACEMENT)
	else:
		ui.global_position = clamp_target(ui.global_position)

## stage 契约：把提议钳制成合法驻留位置（纯计算，不落笔）。
func apply_place(target_ui: Control, proposed: Vector2) -> Vector2:
	if target_ui == null:
		return proposed
	return clamp_for_ui(target_ui, proposed)

## 把目标位置按当前配置钳制成合法驻留位置（对 [member ui] 计算，纯计算不落笔）。
func clamp_target(target: Vector2) -> Vector2:
	if ui == null:
		return target
	return clamp_for_ui(ui, target)

## 对指定控件钳制位置（is_opposite_constraints 模式按控件尺寸翻转边界）。
func clamp_for_ui(target_ui: Control, position: Vector2) -> Vector2:
	var result := position
	if is_opposite_constraints:
		result = _apply_mark_constraints(result + target_ui.size) - target_ui.size
	else:
		result = _apply_mark_constraints(result)
	if is_froce_in_viewports:
		result = _apply_viewport_constraints(result)
	return result

func _apply_mark_constraints(position: Vector2) -> Vector2:
	var result: Vector2 = position
	if mark_max_x_control:
		result.x = min(result.x, mark_max_x_control.global_position.x + mark_max_x_offset)
	if mark_min_x_control:
		result.x = max(result.x, mark_min_x_control.global_position.x + mark_min_x_offset)
	if mark_max_y_control:
		result.y = min(result.y, mark_max_y_control.global_position.y + mark_max_y_offset)
	if mark_min_y_control:
		result.y = max(result.y, mark_min_y_control.global_position.y + mark_min_y_offset)
	return result

## 视口矩形实时读取（缓存会在窗口 resize 后过期）。
func _apply_viewport_constraints(position: Vector2) -> Vector2:
	var rect := Rect2()
	var viewport := get_viewport()
	if viewport != null:
		rect = viewport.get_visible_rect()
	var result: Vector2 = position
	result.x = clampf(position.x, rect.position.x + viewports_min_x_offset, rect.end.x + viewports_max_x_offset)
	result.y = clampf(position.y, rect.position.y + viewports_min_y_offset, rect.end.y + viewports_max_y_offset)
	return result
