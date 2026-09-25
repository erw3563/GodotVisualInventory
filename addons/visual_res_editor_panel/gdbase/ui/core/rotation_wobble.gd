class_name RotationWobble
extends RefCounted
## 通用 UI 共享旋转晃动演出引擎：按停靠角序列逐段旋转（每段可选弹性过冲回弹），
## 播完自动收常态角；播放中再次 play 从当前角度从头重播；段与段之间同帧衔接
## 不漏空闲帧。算法自 RotatePanel 段队列 + 弹性实现整块抽取，面板系与快捷系
## （RotatePanel / QuickRotate）各持独占实例，宿主负责触发与参数导出。
## 引擎只驱动目标控件的 rotation_degrees——mouse_filter、可见性、其它变换与
## 业务信号一归宿主；Tween 经宿主节点创建（宿主退出树前须 abort）。

## 一轮晃动演出完整结束（含收常态段）后发出；stop/abort 不发。
signal finished

## 常态角（度）：每轮演出的终点归宿。
var rest_degrees: float = 0.0

## 停靠角序列（度）：一轮演出依次停靠的角度，播完自动续一段收常态角；
## 正负号决定各段旋转方向；空序列时 play 无演出。
var sequence: Array[float] = []

## 弹性角度（度）：每段到达目标角后沿行进方向继续多转的角度，再回弹收在目标角；
## 0 = 每段单程动画（时长按 70%/30% 分给去程与回程）。
var elastic_degrees: float = 0.0

## 单段动画时长（秒）。
var segment_duration: float = 0.25

## 动画过渡类型（默认 BACK 配 EASE_OUT：越过目标过冲再恰好收敛）。
var transition: Tween.TransitionType = Tween.TRANS_BACK

## 收常态段的缓动类型（去程段固定 EASE_IN 加速离开，与面板口径一致）。
var ease_type: Tween.EaseType = Tween.EASE_OUT

## 是否正在播放一轮晃动（含段间同帧衔接的瞬间）。
var is_playing: bool:
	get:
		return _playing

var _host: Node
var _target: Control
var _queue: Array[float] = []
var _tween: Tween
var _playing := false


## 绑定宿主与驱动目标。宿主提供 Tween 创建（须入树后调用）；目标即被晃动的控件。
func setup(host: Node, target: Control) -> void:
	_host = host
	_target = target


## 播放一轮晃动：依次停靠 sequence 各角后续收常态角；播放中再次调用从当前角度
## 从头重播（清空旧队列）。空序列无演出；目标不在树内时静默跳过。
func play() -> void:
	if _host == null or _target == null or not _target.is_inside_tree():
		return
	if sequence.is_empty():
		return
	_kill_tween()
	_queue = sequence.duplicate()
	_queue.append(rest_degrees)
	_playing = true
	_play_next_segment()


## 停止并收常态：杀 Tween、清队列、立即吸附常态角（不发 finished）。
func stop() -> void:
	abort()
	if _target != null:
		_target.rotation_degrees = rest_degrees


## 中止演出：杀 Tween、清队列，角度停在当前位置（不发 finished）。
func abort() -> void:
	_kill_tween()
	_queue.clear()
	_playing = false


## 当前段的活动 Tween（供编辑器预览的有界等待；无演出时为 null）。
func get_active_tween() -> Tween:
	return _tween


func _play_next_segment() -> void:
	if not _playing:
		return
	if _queue.is_empty():
		_finish()
		return
	var target_angle: float = _queue.pop_front()
	# 收常态段以队列取尽为准（序列中段恰好等于常态角时仍按去程缓动）。
	var is_rest_segment := _queue.is_empty()
	var start_angle := _target.rotation_degrees
	var needs_animation := absf(start_angle - target_angle) > 0.05 \
			or elastic_degrees > 0.0
	if not needs_animation or segment_duration <= 0.0:
		_target.rotation_degrees = target_angle
		_play_next_segment()
		return
	_kill_tween()
	_tween = _host.create_tween()
	_tween.set_trans(transition)
	_tween.set_ease(ease_type if is_rest_segment else Tween.EASE_IN)
	if elastic_degrees <= 0.0:
		_tween.tween_method(
			_set_angle, start_angle, target_angle, segment_duration
		)
	else:
		var delta := target_angle - start_angle
		# 角度差在浮点误差内视为原地回弹，按约定朝正向弹出（signf(0 附近的负 epsilon) 会随机反向）。
		var direction := 1.0 if absf(delta) < 0.05 else signf(delta)
		var overshoot := target_angle + direction * elastic_degrees
		_tween.tween_method(
			_set_angle, start_angle, overshoot, segment_duration * 0.7
		)
		_tween.tween_method(
			_set_angle, overshoot, target_angle, segment_duration * 0.3
		).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_callback(_on_segment_finished.bind(target_angle))


func _on_segment_finished(target_angle: float) -> void:
	_tween = null
	if not _playing:
		return
	_target.rotation_degrees = target_angle
	_play_next_segment()


func _finish() -> void:
	_playing = false
	_tween = null
	_target.rotation_degrees = rest_degrees
	finished.emit()


func _set_angle(value: float) -> void:
	if _target != null:
		_target.rotation_degrees = value


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
