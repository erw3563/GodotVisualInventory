@tool
class_name ItemFrameAnimation
extends ItemAnimationContent

@export var frames: Array[Texture2D] = []
@export var frame_duration := 0.1

func get_channel() -> Channel:
	return Channel.APPEARANCE

func get_duration() -> float:
	return frames.size() * frame_duration

func validate_configuration() -> StringName:
	if not is_finite(frame_duration) or frame_duration <= 0.0:
		return &"invalid_frame_duration"
	if frames.is_empty():
		return &"missing_animation_frames"
	if not is_finite(get_duration()):
		return &"invalid_animation_duration"
	for frame in frames:
		if frame == null:
			return &"missing_frame_texture"
	return &""

func sample(elapsed: float) -> Dictionary:
	var index := mini(int(elapsed / frame_duration), frames.size() - 1)
	return {"texture": frames[index]}
