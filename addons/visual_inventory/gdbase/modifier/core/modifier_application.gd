class_name ModifierApplication
extends Resource
## 与目标领域无关的修饰持续时间与 COUNT 状态。

enum DurationMode {
	WHILE_SOURCE,
	PERMANENT,
	TURN,
	COUNT,
}

@export var duration_mode: DurationMode = DurationMode.WHILE_SOURCE
@export var max_apply_count: int = -1
@export var remaining_apply_count: int = -1

func ensure_remaining_apply_count() -> void:
	if duration_mode != DurationMode.COUNT or remaining_apply_count >= 0 or max_apply_count < 0:
		return
	remaining_apply_count = max_apply_count

func can_apply_new_count() -> bool:
	if duration_mode != DurationMode.COUNT:
		return true
	ensure_remaining_apply_count()
	return max_apply_count < 0 or remaining_apply_count > 0

func consume_apply_count() -> void:
	if duration_mode == DurationMode.COUNT and max_apply_count >= 0:
		remaining_apply_count = maxi(0, remaining_apply_count - 1)

func removes_when_out_of_range() -> bool:
	return duration_mode == DurationMode.WHILE_SOURCE or duration_mode == DurationMode.TURN
