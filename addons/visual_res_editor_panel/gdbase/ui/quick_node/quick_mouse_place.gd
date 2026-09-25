@tool
class_name QuickMousePlace
extends Node
## 负责处理目标控件的位置，根据鼠标坐标、控件尺寸和偏移计算落点。
## 配置 [member placer] 时，以 PLACEMENT 意图提交位置；placer 留空时直接设置位置。
## 统一播放契约：[method play] 执行一次定位，同步完成后发出 [signal play_finished]。

signal play_finished

@export var control: Control
## 强制 control 控件全部显示在屏幕内
@export var is_show_in_viewport: bool = true
## 将控件顶点对齐鼠标；启用视口约束时，根据可用空间选择对齐顶点。
@export var is_point_in_mouse_pos: bool = true
## 控件在x轴上是否居中,居中优先级低于强制全部显示与强制处于顶点
@export var is_control_x_center: bool = false
## 控件在y轴上是否居中,居中优先级低于强制全部显示与强制处于顶点
@export var is_control_y_center: bool = false
## 控件与鼠标位置的偏移
@export var offset: Vector2
## 定位前通过 Control.reset_size 将控件尺寸调整为内容最小尺寸。
@export var shrink_to_content: bool = true
## 接收定位请求的节点，提供 place(control, proposed, intent) 方法。
## 定位请求使用 PLACEMENT 意图；placer 留空时直接设置位置。
@export var placer: Node


## 统一播放契约：定位到鼠标处——先按最小尺寸算定位（隐藏状态下 size 即最小大小），
## 落笔经仲裁者钳制后同步发完成信号。返回值表示目标控件存在并已执行定位调用。
func play() -> bool:
	if control == null:
		return false
	if shrink_to_content:
		control.reset_size()
	var new_pos := control.get_global_mouse_position()
	if not is_point_in_mouse_pos:
		if is_control_x_center:
			new_pos.x -= control.size.x / 2
		if is_control_y_center:
			new_pos.y -= control.size.y / 2
	if is_show_in_viewport:
		if is_point_in_mouse_pos:
			# 顶点策略：越界的一侧整体翻到鼠标另一侧
			var viewport_rect := control.get_viewport_rect()
			if new_pos.x + control.size.x > viewport_rect.end.x:
				new_pos.x -= control.size.x
			if new_pos.y + control.size.y > viewport_rect.end.y:
				new_pos.y -= control.size.y
		else:
			new_pos = _clamp_rect_inside_viewport(new_pos)
	_place_proposed(new_pos + offset)
	play_finished.emit()
	return true


## 通过 placer 提交定位意图；placer 留空时设置控件的全局位置。
func _place_proposed(proposed: Vector2) -> void:
	if placer != null and placer.has_method("place"):
		placer.place(control, proposed, QuickUI.PlaceIntent.PLACEMENT)
	else:
		control.global_position = proposed


## 把整块控件（含尺寸）钳进视口。
func _clamp_rect_inside_viewport(pos: Vector2) -> Vector2:
	var viewport_rect := control.get_viewport_rect()
	var result := pos
	result.x = clampf(result.x, viewport_rect.position.x, viewport_rect.end.x)
	result.y = clampf(result.y, viewport_rect.position.y, viewport_rect.end.y)
	result.x = clampf(result.x + control.size.x, viewport_rect.position.x, viewport_rect.end.x) - control.size.x
	result.y = clampf(result.y + control.size.y, viewport_rect.position.y, viewport_rect.end.y) - control.size.y
	return result
