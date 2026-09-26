class_name ItemAnimationPlaybackHandle
extends RefCounted
## 终态一次落定；同步跳过亦可安全等待。
signal finished
enum Status { RUNNING, COMPLETED, CANCELLED, REPLACED, IGNORED, SKIPPED, REJECTED }
var status: Status = Status.RUNNING
var reason_key: StringName
var child_results: Array[Dictionary] = []
var _command: Callable

func is_finished() -> bool:
	return status != Status.RUNNING

func cancel() -> void:
	_request_end(Status.CANCELLED, &"cancelled")

func finish() -> void:
	_request_end(Status.COMPLETED, &"")

func _request_end(end_status: Status, reason: StringName) -> void:
	if is_finished():
		return
	if _command.is_valid():
		_command.call(end_status, reason)
	else:
		settle(end_status, reason)

func settle(end_status: Status, reason: StringName = &"") -> void:
	if is_finished() or end_status == Status.RUNNING:
		return
	status = end_status
	reason_key = reason
	_command = Callable()
	finished.emit()

func wait_until_finished(tree: SceneTree, timeout_seconds := 5.0) -> Status:
	if is_finished():
		return status
	if tree == null or not is_finite(timeout_seconds) or timeout_seconds <= 0.0:
		_request_end(Status.CANCELLED, &"invalid_wait_timeout")
		return status
	var deadline := Time.get_ticks_msec() + int(timeout_seconds * 1000.0)
	while not is_finished():
		if Time.get_ticks_msec() >= deadline:
			_request_end(Status.CANCELLED, &"playback_timeout")
			break
		await tree.process_frame
	return status
