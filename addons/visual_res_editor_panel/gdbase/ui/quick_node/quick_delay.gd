class_name QuickDelay
extends Node
## 延时步骤：QuickUiAnimHost 树序时间线中的间隔表达——插在宿主子节点序里即表达
## 「过一段再播」。实现统一播放契约（[method play]）：播放即起计时，超时发
## [signal play_finished]；宿主据此等完间隔再走下一步。
## 时长 ≤ 0 视为无操作（play 返回 false，不占时间线）。
## 播放中再次 play 从头重计（旧计时作废不发信号）。
## 节点退出树后未超时的计时静默作废（不发信号）。

signal play_finished

## 间隔时长（秒）；≤ 0 视为无操作跳过。
@export_range(0.0, 10.0, 0.01) var duration := 0.25

var _run_token := 0


func play() -> bool:
	if duration <= 0.0:
		return false
	_run_token += 1
	_delay_async(_run_token)
	return true


func _delay_async(token: int) -> void:
	await get_tree().create_timer(duration).timeout
	if not is_instance_valid(self) or not is_inside_tree() or token != _run_token:
		return
	play_finished.emit()
