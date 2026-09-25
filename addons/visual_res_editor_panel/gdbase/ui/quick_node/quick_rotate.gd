@tool
class_name QuickRotate
extends Node
## 旋转演出件：把宿主 [Control] 从当前旋转播放到 [member target_rotation_degrees]。
## 统一播放契约 play＋play_finished；[method is_rotating] 为播放查询。
## 所有权契约：只驱动 [member ui] 的 rotation，不改 scale / pivot_offset / modulate.a /
## visible / mouse_filter / position / size；因此与 QuickZoom、QuickWobble、位置类演出件
## 可叠加挂在同一控件上。起点即宿主的当前旋转角。
## 编辑器内提供 Inspector「动画预览」单次演出（机制见 ui/core AnimationPreview）。

signal play_finished

## 要驱动的宿主控件；为空则尝试使用本组件的父节点（若为 Control）。
@export var ui: Control

@export_group("播放效果")
## 目标旋转角（度）：play 从当前角到达该值。
@export_range(-720.0, 720.0, 0.1, "degrees", "or_less", "or_greater") var target_rotation_degrees: float = 0.0
## 旋转动画时长（秒）。
@export_range(0.0, 3.0, 0.01) var animation_duration: float = 0.32
## 动画过渡类型。
@export var animation_transition: Tween.TransitionType = Tween.TRANS_CUBIC
## 动画缓动类型。
@export var animation_ease: Tween.EaseType = Tween.EASE_OUT

@export_group("动画预览")
## 仅编辑器生效的单次演出预览；运行时调用无副作用。
@export_tool_button("播放一次", "Play") var preview_play_action: Callable = preview_play
@export_tool_button("停止并恢复", "Stop") var preview_stop_action: Callable = preview_stop

var _tween: Tween
## 宿主级整树预览会话标记（编辑器内由 QuickUiAnimHost 开关）。
var _host_preview_active := false


## 自身旋转是否进行中。
func is_rotating() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()


func _exit_tree() -> void:
	preview_stop()
	_kill_tween()


## 统一播放契约：从当前旋转角到达 [member target_rotation_degrees]；已处目标且未在
## 播放则无操作。返回是否实际起播；播放中再次 play 杀旧建新、从当前角重播。
func play() -> bool:
	_resolve_ui()
	if ui == null:
		return false
	if not is_rotating() and is_equal_approx(ui.rotation_degrees, target_rotation_degrees):
		return false
	_run_tween()
	return true


## 收回旋转写入：取消进行中的旋转，角停在当前帧（宿主取消树序播放时调用）。
func interrupt() -> void:
	_kill_tween()


func _run_tween() -> void:
	_kill_tween()
	if ui == null:
		return
	if animation_duration <= 0.0:
		ui.rotation_degrees = target_rotation_degrees
		_emit_finished()
		return
	_tween = create_tween()
	_tween.set_trans(animation_transition).set_ease(animation_ease)
	_tween.tween_property(ui, "rotation_degrees", target_rotation_degrees, animation_duration)
	_tween.finished.connect(func():
		if ui != null:
			ui.rotation_degrees = target_rotation_degrees
		_emit_finished(), CONNECT_ONE_SHOT)


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


func _resolve_ui() -> void:
	if ui != null:
		return
	var parent_node := get_parent()
	if parent_node is Control:
		ui = parent_node as Control


func _emit_finished() -> void:
	if not Engine.is_editor_hint() or _host_preview_active:
		play_finished.emit()


func _begin_host_preview_session() -> void:
	_host_preview_active = true


func _end_host_preview_session() -> void:
	_host_preview_active = false
	_kill_tween()


#region 编辑器单次预览

var _preview := AnimationPreview.new()


## 仅在编辑器播放一次：从当前角到达目标后恢复编辑状态。
func preview_play() -> void:
	if not Engine.is_editor_hint():
		return
	preview_stop()
	_stop_sibling_previews()
	_resolve_ui()
	if ui == null:
		push_warning("QuickRotate：目标控件缺失（ui 未导出且父节点不是 Control），无法预览。")
		return
	var properties: Array[StringName] = []
	properties.append_array(AnimationPreview.PRESENTATION_PROPERTIES)
	properties.append_array(AnimationPreview.GEOMETRY_PROPERTIES)
	if not _preview.begin(ui, properties, false):
		return
	_preview_run(_preview.generation)


func is_previewing() -> bool:
	return _preview.is_active()


func preview_stop() -> void:
	if not is_previewing():
		return
	_kill_tween()
	_preview.stop()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		preview_stop()


func _stop_sibling_previews() -> void:
	var parent_node := get_parent()
	if parent_node == null:
		return
	if parent_node.has_method("preview_stop"):
		parent_node.call("preview_stop")
	for child in parent_node.get_children():
		if child != self and child.has_method("preview_stop"):
			child.call("preview_stop")


func _preview_run(token: int) -> void:
	await get_tree().process_frame
	if not _preview.is_current(token) or not is_inside_tree():
		return
	play()
	await _preview.wait_tween(self, _tween, token, animation_duration + 2.0)
	if _preview.is_current(token):
		preview_stop()

#endregion
