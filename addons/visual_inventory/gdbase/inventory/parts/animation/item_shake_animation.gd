@tool
class_name ItemShakeAnimation
extends ItemAnimationContent

@export var angle_degrees := 12.0
@export var cycles := 3
@export var duration := 0.4

func get_channel() -> Channel:
	return Channel.FEEDBACK

func get_duration() -> float:
	return duration

func validate_configuration() -> StringName:
	if not is_finite(duration) or duration <= 0.0:
		return &"invalid_shake_duration"
	if cycles <= 0:
		return &"invalid_shake_cycles"
	if not is_finite(angle_degrees):
		return &"invalid_shake_angle"
	return &""

func sample(elapsed: float) -> Dictionary:
	var progress := clampf(elapsed / duration, 0.0, 1.0)
	return {"rotation": sin(progress * TAU * cycles) * deg_to_rad(angle_degrees) * (1.0 - progress)}
