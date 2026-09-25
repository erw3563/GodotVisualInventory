@tool
class_name QuickShow
extends Node
## 显隐演出件：负责目标控件的目标显隐状态——检查器声明 [member target_state]
## （显示或隐藏），统一播放契约 [method play] 从当前表现态到达该目标（内置淡入
## 淡出，时长 0 直接落位），完成发 [signal play_finished]（时长 0 当帧发射；有动画
## 则随动画结束发射）。装载铺场契约 [method prepare_play]：目标为显示的件由宿主
## 在装载时瞬时隐藏，弥合装载帧到起播前的闪现；一个节点只负责一条显隐路径，双向
## 由两个目标不同的实例分属两个宿主表达。
## 编辑器内提供 Inspector「动画预览」单次演出（仅编辑器生效，机制见 ui/core
## AnimationPreview）；编辑器空闲态动画路径全隔离。

signal play_finished

## 显隐目标状态：播放到达显示（淡入显形）或隐藏（淡出收起）。
enum TargetState {
	SHOW, ## 显示：淡入显形
	HIDE, ## 隐藏：淡出收起
}

@export var control: Control

## 目标显隐状态：play 从当前表现态到达该状态；检查器中只能赋值为目标状态。
@export var target_state: TargetState = TargetState.SHOW

@export_group("播放效果")
## 淡入淡出时长（秒）；0 视为立即完成（当帧落位并同步发完成信号）。
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var animation_duration: float = 0.25

## 动画过渡类型。
@export var animation_transition: Tween.TransitionType = Tween.TRANS_CUBIC

## 动画缓动类型。
@export var animation_ease: Tween.EaseType = Tween.EASE_OUT

@export_group("动画预览")
## 仅编辑器生效的单次演出预览（快照与恢复由共享 AnimationPreview 承载，播放经
## 统一 play 方法）；运行时调用保持无副作用。
@export_tool_button("播放一次", "Play") var preview_play_action: Callable = preview_play
@export_tool_button("停止并恢复", "Stop") var preview_stop_action: Callable = preview_stop

## 淡入淡出 Tween。
var _fade_tween: Tween
## 宿主级整树预览会话标记（编辑器内由 QuickUiAnimHost 开关）：开启时等效本组件预览——
## 解锁编辑器动画隔离与完成信号发射。
var _host_preview_active := false


func _exit_tree() -> void:
	preview_stop()
	_kill_fade_tween()


## 统一播放契约：从当前表现态到达 [member target_state]；已处目标且无进行中的
## 动画则无操作。返回是否实际起播或正在播（false = 已处终态或目标缺失，宿主据此
## 把该步视为无操作跳过）；动画进行中再次 play 从当前表现重启到达目标。
func play() -> bool:
	if control == null:
		return false
	var shown := target_state == TargetState.SHOW
	if not is_animating() and shown == control.visible:
		return false
	_set_target(shown)
	return true


## 自身淡入淡出是否进行中（供终态守卫与联动方判断完成时机）。
func is_animating() -> bool:
	return _fade_tween != null and _fade_tween.is_valid() and _fade_tween.is_running()


## 装载铺场契约（宿主装载时调用）：目标为显示的件先把控件瞬时隐藏——弥合装载帧
## 到起播前的闪现；目标为隐藏的件保持现状（其控件的呈现由显示路径维护）。
func prepare_play() -> void:
	if Engine.is_editor_hint() or control == null:
		return
	if target_state == TargetState.SHOW:
		_set_target_instantly(false)


func _set_target(shown: bool) -> void:
	if Engine.is_editor_hint() and not is_previewing() and not _host_preview_active:
		return
	if animation_duration > 0.0:
		_play_fade(shown)
		return
	_set_target_instantly(shown)
	_emit_finished()


## 瞬时落位（铺场与时长 0 路径）：visible 直接切换并归位透明度。
func _set_target_instantly(shown: bool) -> void:
	control.modulate.a = 1.0
	if shown:
		control.show()
	else:
		control.hide()


## 淡入淡出：到达显示先可见再从 0 淡入，到达隐藏淡出结束后才隐藏；完成信号随动画
## 结束发射。中途反转杀旧建新，被替换的动画保持静默。
func _play_fade(shown: bool) -> void:
	_kill_fade_tween()
	_fade_tween = create_tween()
	_fade_tween.set_trans(animation_transition).set_ease(animation_ease)
	if shown:
		control.visible = true
		control.modulate.a = 0.0
		_fade_tween.tween_property(control, "modulate:a", 1.0, animation_duration)
	else:
		_fade_tween.tween_property(control, "modulate:a", 0.0, animation_duration)
	_fade_tween.finished.connect(func() -> void:
		if not shown:
			_set_target_instantly(false)
		_emit_finished())


func _kill_fade_tween() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null


## 业务信号仅在运行时发射——编辑器空闲（含本组件单次预览）静默；宿主整树预览
## 会话期间放行（宿主预览的步骤等待依赖完成信号，见预览规范）。
func _emit_finished() -> void:
	if not Engine.is_editor_hint() or _host_preview_active:
		play_finished.emit()


## 宿主级整树预览会话开启（QuickUiAnimHost 编辑器预览调用）：解锁编辑器动画隔离
## 与完成信号发射，并把表现铺垫到起播前置态（目标显示的件瞬时隐藏；快照在会话
## 开启前完成，铺垫随预览回滚）。
func _begin_host_preview_session() -> void:
	_host_preview_active = true
	if control != null and target_state == TargetState.SHOW:
		_set_target_instantly(false)


## 宿主级整树预览会话结束：杀进行中的显隐动画（表现态由宿主快照恢复）。
func _end_host_preview_session() -> void:
	_host_preview_active = false
	_kill_fade_tween()


#region 编辑器单次预览

var _preview := AnimationPreview.new()


## 仅在编辑器播放一次：铺垫起播前置态（目标显示的件先瞬时隐藏）后播放到达目标，
## 结束后恢复编辑状态；再次点击从原编辑状态重新开始。
func preview_play() -> void:
	if not Engine.is_editor_hint():
		return
	preview_stop()
	_stop_sibling_previews()
	if control == null:
		push_warning("QuickShow：目标控件缺失（control 未导出），无法预览。")
		return
	var properties: Array[StringName] = []
	properties.append_array(AnimationPreview.PRESENTATION_PROPERTIES)
	properties.append_array(AnimationPreview.GEOMETRY_PROPERTIES)
	if not _preview.begin(control, properties, false):
		return
	_preview_run(_preview.generation)


func is_previewing() -> bool:
	return _preview.is_active()


## 保存前和退出树同步恢复；不依赖 Inspector 选择或插件生命周期。
func preview_stop() -> void:
	if not is_previewing():
		return
	_kill_fade_tween()
	_preview.stop()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		preview_stop()


## 同目标互斥：起播前停掉同级其它演出组件的预览会话——两个组件并发预览同一
## 宿主会互相踩对方的快照恢复；宿主（QuickUiAnimHost）名下时先停宿主的预览会话。
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
	if target_state == TargetState.SHOW:
		_set_target_instantly(false)
	play()
	await _preview.wait_tween(self, _fade_tween, token, animation_duration + 2.0)
	if _preview.is_current(token):
		preview_stop()

#endregion
