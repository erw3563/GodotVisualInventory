@tool
class_name QuickWobble
extends Node
## 晃动演出件：播放一次旋转晃动——依次停靠 [member wobble_sequence] 各角度后归
## 常态角 0；播放中再次 play 从头重播。演出引擎为共享 [class RotationWobble]，本组件
## 独占一个实例；统一播放契约 play＋play_finished，[method is_wobbling] 为播放查询。
## 所有权契约：只驱动 [member ui] 的 rotation，不改 scale / pivot_offset / modulate.a /
## visible / mouse_filter / global_position / size，真实布局全程不变；因此与
## QuickZoom（缩放）、QuickConstraints（含 continuous）和位置类演出件互不冲突，
## 可叠加挂在同一控件上。
## 编辑器内提供 Inspector「动画预览」单次演出（仅编辑器生效，机制见 ui/core
## AnimationPreview）。

signal play_finished

## 要驱动的宿主控件；为空则尝试使用本组件的父节点（若为 Control）。
@export var ui: Control

@export_group("播放效果")
## 晃动停靠角序列（度）：一轮演出依次停靠的角度，播完自动归 0；
## 正负号决定各段旋转方向；空序列时播放无演出。
@export var wobble_sequence: Array[float] = [-25.0]:
	set(value):
		wobble_sequence = value
		_wobble.sequence = value

## 弹性角度（度）：每段到达目标角后沿行进方向继续多转的角度，再回弹收在目标角；
## 0 = 每段单程动画（时长按 70%/30% 分给去程与回程）。
@export_range(0.0, 360.0, 0.1, "degrees") var elastic_degrees: float = 0.0:
	set(value):
		elastic_degrees = value
		_wobble.elastic_degrees = value

## 单段晃动动画时长（秒）
@export_range(0.0, 2.0, 0.01) var animation_duration: float = 0.25:
	set(value):
		animation_duration = value
		_wobble.segment_duration = value

## 动画过渡类型（默认 BACK 配 EASE_OUT：越过目标过冲再恰好收敛）
@export var animation_transition: Tween.TransitionType = Tween.TRANS_BACK:
	set(value):
		animation_transition = value
		_wobble.transition = value

## 归零段的缓动类型（去程段固定用 EASE_IN 加速离开）
@export var animation_ease: Tween.EaseType = Tween.EASE_OUT:
	set(value):
		animation_ease = value
		_wobble.ease_type = value

@export_group("动画预览")
## 仅编辑器生效的单次演出预览（仅编辑器生效，机制见 ui/core AnimationPreview）；
## 运行时调用保持无副作用。
@export_tool_button("播放一次", "Play") var preview_play_action: Callable = preview_play
@export_tool_button("停止并恢复", "Stop") var preview_stop_action: Callable = preview_stop

## 是否正在播放晃动演出
func is_wobbling() -> bool:
	return _wobble.is_playing

var _wobble := RotationWobble.new()
## 宿主级整树预览会话标记（编辑器内由 QuickUiAnimHost 开关）：开启时等效本组件预览——
## 解锁完成信号转发。
var _host_preview_active := false


func _ready() -> void:
	_resolve_ui()
	# 编辑器空闲不接完成信号转发（单次预览经引擎直驱、不依赖信号）；宿主预览会话
	# 开启时现补转发。
	if ui != null and not Engine.is_editor_hint():
		_ensure_wobble_engine()


func _exit_tree() -> void:
	preview_stop()
	_wobble.abort()


## 统一播放契约：播放一轮晃动（依次停靠 wobble_sequence 后归 0）；播放中调用从头
## 重播。返回是否实际起播（空序列或目标缺失返回 false，宿主据此把该步视为无操作
## 跳过）。
func play() -> bool:
	_resolve_ui()
	if ui == null or wobble_sequence.is_empty():
		return false
	_sync_wobble_config()
	_wobble.play()
	return true


## 装配晃动引擎并幂等接上完成信号转发：运行时 _ready 与编辑器宿主预览会话共用
## ——编辑器 _ready 不初始化引擎，而宿主整树预览经真实树序等待 play_finished，
## 会话开启时必须补上转发连接，否则该步骤只能等超时兜底空转。
func _ensure_wobble_engine() -> void:
	_wobble.setup(self, ui)
	if not _wobble.finished.is_connected(_forward_finished):
		_wobble.finished.connect(_forward_finished)


func _forward_finished() -> void:
	play_finished.emit()


func _sync_wobble_config() -> void:
	_wobble.sequence = wobble_sequence
	_wobble.elastic_degrees = elastic_degrees
	_wobble.segment_duration = animation_duration
	_wobble.transition = animation_transition
	_wobble.ease_type = animation_ease


## 若未指定 ui，则当父节点为 Control 时将其作为驱动目标。
func _resolve_ui() -> void:
	if ui != null:
		return
	var p := get_parent()
	if p is Control:
		ui = p as Control


## 宿主级整树预览会话开启（QuickUiAnimHost 编辑器预览调用）：编辑器 _ready 不初始化
## 演出引擎，此处现补绑定并把目标归零到常态角（表现态由宿主的 AnimationPreview
## 快照恢复）。
func _begin_host_preview_session() -> void:
	_host_preview_active = true
	_resolve_ui()
	if ui != null:
		_ensure_wobble_engine()
		ui.rotation_degrees = 0.0


## 宿主级整树预览会话结束：中止进行中的晃动（角度停在当前位置，表现态由宿主
## 快照恢复）。
func _end_host_preview_session() -> void:
	_host_preview_active = false
	_wobble.abort()


#region 编辑器单次预览

var _preview := AnimationPreview.new()


## 仅在编辑器播放一轮晃动；再次点击从原编辑状态重新开始。
func preview_play() -> void:
	if not Engine.is_editor_hint():
		return
	preview_stop()
	_stop_sibling_previews()
	_resolve_ui()
	if ui == null:
		push_warning("QuickWobble：目标控件缺失（ui 未导出且父节点不是 Control），无法预览。")
		return
	# 编辑器 _ready 不初始化引擎，预览前现补绑定与参数。
	_wobble.setup(self, ui)
	_sync_wobble_config()
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
	_wobble.abort()
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
	ui.visible = true
	ui.rotation_degrees = 0.0
	var segment_count := maxi(1, wobble_sequence.size() + 1)
	var total_timeout := segment_count * (animation_duration + 2.0)
	play()
	while _preview.is_current(token) and is_wobbling():
		if not await _preview.wait_tween(
				self, _wobble.get_active_tween(), token, total_timeout):
			break
	if _preview.is_current(token):
		preview_stop()

#endregion
