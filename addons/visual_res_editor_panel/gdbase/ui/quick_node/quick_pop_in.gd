@tool
class_name QuickPopIn
extends Node
## 位置演出件（入场方向）：把 [Control] 从当前布局位置 tween 到 [member target_ratio]
## 指定的视口位置。统一播放契约 [method play] ＋ [signal play_finished]；负责布局
## position 的写入——visible / modulate 归 QuickShow，scale / pivot 归 QuickZoom。
## 目标位置按视口比例声明：控件上 [member origin_ratio] 指定的贴合点对齐 视口尺寸 ×
## [member target_ratio]，默认中心贴合，0.5, 0.5 即屏幕中心，任一分量越出 0~1 即落在
## 屏外。目标位置是本件唯一的播放输入，起播值取控件当前表现位，屏外起点由场景与
## 调用方摆放。本件独立可用：把自身挂在宿主名下由宿主树序驱动，散装摆放时由调用方
## 直接 [method play]。
## [member fly_mode] 选飞行样式：LINE 沿起点与落点的连线插值；PROJECTILE 按驱动控件
## 朝向取出射方向、由 [method play] 反解初速与重力，走常加速度抛物线落回同一个落点
## （解不出可行弧线时本次按 LINE 播放）。
## 编辑器内提供 Inspector「动画预览」单次演出（仅编辑器生效，机制见 ui/core
## AnimationPreview）；运行时调用保持无副作用。

signal play_finished

## 飞行样式：LINE 沿起点与落点连线插值，PROJECTILE 按驱动控件朝向抛射。
enum FlyMode {
	LINE,        ## 沿起点与落点的连线插值到落点。
	PROJECTILE,  ## 按驱动控件朝向解算初速与重力，走抛物线到落点。
}

## 要驱动的 UI 根节点；为空则尝试使用本组件的父节点（若为 Control）。
@export var ui: Control

@export_group("播放效果")
## 飞行样式：LINE 沿起点与落点的连线插值，PROJECTILE 按驱动控件朝向抛射。
@export var fly_mode: FlyMode = FlyMode.LINE
## 贴合点在控件内的比例坐标（0~1；默认中心，四角可设 0/1）：该点对齐
## [member target_ratio] 声明的目标位置。
@export var origin_ratio: Vector2 = Vector2(0.5, 0.5)
## 目标位置（视口比例）：控件上 [member origin_ratio] 指定的贴合点对齐 视口尺寸 ×
## 该比例；0.5, 0.5 为屏幕中心，任一分量越出 0~1 即落在屏外。
@export var target_ratio: Vector2 = Vector2(0.5, 0.5)
## 入场动画时长（秒）；命名对齐 QuickZoom / QuickWobble 与面板系的 animation_duration。
@export_range(0.05, 3.0, 0.01) var animation_duration: float = 0.45
## 直线样式的入场过渡类型。
@export var animation_transition: Tween.TransitionType = Tween.TRANS_CUBIC
## 直线样式的入场缓动类型。
@export var animation_ease: Tween.EaseType = Tween.EASE_OUT

@export_group("动画预览")
## 仅编辑器生效的单次演出预览（快照与恢复由共享 AnimationPreview 承载）；
## 运行时调用无副作用。
@export_tool_button("播放一次", "Play") var preview_play_action: Callable = preview_play
@export_tool_button("停止并恢复", "Stop") var preview_stop_action: Callable = preview_stop

var _tween: Tween
## 宿主级整树预览会话标记（编辑器内由 QuickUiAnimHost 开关）：开启时等效本组件预览——
## 解锁编辑器空闲的完成信号发射。
var _host_preview_active := false
## 本次演出的落点（全局坐标）：起播帧定型。
var _landing := Vector2.ZERO
## 抛射样式的出射方向（起播帧按驱动控件朝向定型，见 [method _solve_projectile]）。
var _launch_direction := Vector2.RIGHT
## 抛射样式的初速大小（沿出射方向，起播帧由落点与时长反解）。
var _launch_speed := 0.0
## 抛射样式的重力标量（屏幕 +y 向下，起播帧由落点与时长反解）。
var _flight_gravity := 0.0
## 抛射样式的起点（全局坐标，起播帧定型）。
var _flight_start := Vector2.ZERO
## 本次飞行是否走抛射轨迹（起播帧解算成功时置真）。
var _projectile_flight := false


## 节点退出树时终止未完成的 Tween，避免悬空引用。
func _exit_tree() -> void:
	preview_stop()
	_kill_tween()


## 统一播放契约（宿主经树序时间线驱动）：从控件当前布局位置到达 [member target_ratio]
## 指定的视口位置；已处目标位且动画静止则无操作。返回是否实际起播（false = 已处终态
## 或目标缺失，宿主据此把该步视为无操作跳过）；播放中再次 play 杀旧 tween、从当前
## 位置重播。抛射样式在起播帧解算出射方向、初速与重力，解不出可行弧线时本次按直线
## 样式播放。
func play() -> bool:
	_resolve_ui()
	if ui == null:
		return false
	if not is_animating() and _at_target():
		return false
	_landing = target_global()
	_projectile_flight = fly_mode == FlyMode.PROJECTILE and _solve_projectile()
	_run_tween()
	return true


## 自身位移是否进行中（供终态守卫与联动方判断完成时机）。
func is_animating() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()


## 收回位置写入：取消进行中的位移动画，控件停在当前帧的位置（宿主取消树序播放时
## 调用；被杀的 Tween 不发 [signal play_finished]）。
func interrupt() -> void:
	_kill_tween()


## 目标位置的全局坐标：控件上 [member origin_ratio] 指定的贴合点对齐 视口尺寸 ×
## [member target_ratio] 时的布局原点位。
func target_global() -> Vector2:
	_resolve_ui()
	if ui == null:
		return Vector2.ZERO
	return _viewport_size() * target_ratio - ui.size * _clamped_origin_ratio()


## 贴合点在控件内的偏移量：比例坐标钳到 0~1，贴合点落在控件矩形内。
func _clamped_origin_ratio() -> Vector2:
	return Vector2(clampf(origin_ratio.x, 0.0, 1.0), clampf(origin_ratio.y, 0.0, 1.0))


## 若未指定 ui，则当父节点为 Control 时将其作为驱动目标。
func _resolve_ui() -> void:
	if ui != null:
		return
	var p := get_parent()
	if p is Control:
		ui = p as Control


## 控件当前布局位是否已落在目标位（按布局原点比较，容差半个像素）。
func _at_target() -> bool:
	return QuickUI.layout_to_global(ui, ui.position).distance_to(target_global()) < 0.5


## 按驱动控件朝向解算抛射轨迹：出射方向取控件本地 +X 轴在全局坐标系中的方向（父级
## 旋转与翻转一并计入），初速大小与重力标量由「飞行 animation_duration 秒后精确落在
## 定型落点」反解——D = e·s·T + (0, 0.5·g)·T²，消元得 s = D.x / (T·cos φ)、
## g = 2·(D.y − D.x·tan φ) / T²。
## 返回是否有解：时长为 0、朝向背对目标、朝向正对目标（重力为零）、朝向落到目标线
## 下方或解非有限时返回 false，本次飞行按直线样式播放。
func _solve_projectile() -> bool:
	if ui == null or animation_duration <= 0.0:
		return false
	var direction := ui.get_global_transform().basis_xform(Vector2.RIGHT)
	if direction.length_squared() < 0.000001:
		return false
	direction = direction.normalized()
	var start := QuickUI.layout_to_global(ui, ui.position)
	var delta := _landing - start
	var cos_angle := direction.x
	if absf(cos_angle) < 0.0001 or cos_angle * delta.x <= 0.0:
		return false
	var speed := delta.x / (animation_duration * cos_angle)
	var gravity := 2.0 * (delta.y - delta.x * direction.y / direction.x) \
		/ (animation_duration * animation_duration)
	if not is_finite(speed) or not is_finite(gravity) or gravity <= 0.0:
		return false
	_launch_direction = direction
	_launch_speed = speed
	_flight_gravity = gravity
	_flight_start = start
	return true


## 创建并播放入场动画：直线样式位移到目标位；抛射样式每帧按起播帧定型的全局轨迹求位。
## 结束时发 [signal play_finished]。宿主在步骤完成后把落点经自身管道登记为最终休息位。
func _run_tween() -> void:
	_kill_tween()
	if ui == null:
		return
	if animation_duration <= 0.0:
		ui.position = QuickUI.global_to_layout(ui, _landing)
		_emit_finished()
		return
	if _projectile_flight:
		# 时间曲线由重力项承担：直线时间参数配线性过渡。
		_tween = create_tween().set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
		_tween.tween_method(_place_step, 0.0, 1.0, animation_duration)
		_tween.finished.connect(func():
			_place_step(1.0)
			_settle_landing.call_deferred()
			_emit_finished(), CONNECT_ONE_SHOT)
		return
	_tween = create_tween()
	_tween.set_trans(animation_transition).set_ease(animation_ease)
	_tween.tween_property(
		ui, "position", QuickUI.global_to_layout(ui, _landing), animation_duration
	)
	_tween.finished.connect(func():
		_emit_finished(), CONNECT_ONE_SHOT)


## 帧末再落一次终点：按起播帧定型的全局落点换算布局位，保证终态精确停位。
func _settle_landing() -> void:
	if ui == null or not is_instance_valid(ui):
		return
	ui.position = QuickUI.global_to_layout(ui, _landing)


## 抛射单帧落笔：按起播帧定型的全局轨迹（起点、出射方向、初速、重力、时长）求位后
## 换算布局位。
func _place_step(progress: float) -> void:
	if ui == null:
		return
	var elapsed := clampf(progress, 0.0, 1.0) * animation_duration
	var global := _flight_start \
		+ _launch_direction * (_launch_speed * elapsed) \
		+ Vector2(0.0, 0.5 * _flight_gravity * elapsed * elapsed)
	ui.position = QuickUI.global_to_layout(ui, global)


## 业务信号仅在运行时发射——编辑器空闲（含本组件单次预览）静默；宿主整树预览
## 会话期间放行（宿主预览的步骤等待依赖完成信号，见预览规范）。
func _emit_finished() -> void:
	if not Engine.is_editor_hint() or _host_preview_active:
		play_finished.emit()


## 停止并清空当前 Tween，便于启动新动画。
func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


## 当前视口可见区域尺寸；无视口时返回默认 1920×1080。
func _viewport_size() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return Vector2(1920, 1080)
	return vp.get_visible_rect().size


## 宿主级整树预览会话开启（QuickUiAnimHost 编辑器预览调用）：解锁完成信号发射；
## authored 表现由宿主的 AnimationPreview 快照恢复。
func _begin_host_preview_session() -> void:
	_host_preview_active = true


## 宿主级整树预览会话结束：杀进行中的位移动画。
func _end_host_preview_session() -> void:
	_host_preview_active = false
	_kill_tween()


#region 编辑器单次预览

var _preview := AnimationPreview.new()


## 仅在编辑器播放一次：把控件临时摆到演示起点后播放到位，结束后恢复编辑状态；
## 再次点击从原编辑状态重新开始。
func preview_play() -> void:
	if not Engine.is_editor_hint():
		return
	preview_stop()
	_stop_sibling_previews()
	_resolve_ui()
	if ui == null:
		push_warning("QuickPopIn：目标控件缺失（ui 未导出且父节点不是 Control），无法预览。")
		return
	var properties: Array[StringName] = []
	properties.append_array(AnimationPreview.PRESENTATION_PROPERTIES)
	properties.append_array(AnimationPreview.GEOMETRY_PROPERTIES)
	if not _preview.begin(ui, properties, false):
		return
	_preview_run(_preview.generation)


func is_previewing() -> bool:
	return _preview.is_active()


## 保存前和退出树同步恢复；不依赖 Inspector 选择或插件生命周期。
func preview_stop() -> void:
	if not is_previewing():
		return
	_kill_tween()
	_preview.stop()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		preview_stop()


## 同目标互斥：起播前停掉同级其它演出组件的预览会话——两个组件并发预览同一
## 宿主会互相踩对方的快照恢复；宿主（QuickUiAnimHost）名下时先停宿主的整树预览会话。
func _stop_sibling_previews() -> void:
	var parent := get_parent()
	if parent == null:
		return
	if parent.has_method("preview_stop"):
		parent.call("preview_stop")
	for child in parent.get_children():
		if child != self and child.has_method("preview_stop"):
			child.call("preview_stop")


func _preview_run(token: int) -> void:
	# 等当前布局帧完成；停止或重播后旧轮不能再初始化。
	await get_tree().process_frame
	if not _preview.is_current(token) or not is_inside_tree():
		return
	_place_preview_start()
	play()
	await _preview.wait_tween(self, _tween, token, animation_duration + 2.0)
	if _preview.is_current(token):
		preview_stop()


## 演示起点：贴合点沿 y 轴退一屏（控件回到屏外一侧），本轮预览的位移由此产生；
## 位置随 AnimationPreview 快照一并恢复。
func _place_preview_start() -> void:
	ui.position = QuickUI.global_to_layout(
		ui,
		_viewport_size() * (target_ratio - Vector2(0.0, 1.0)) - ui.size * _clamped_origin_ratio()
	)

#endregion
