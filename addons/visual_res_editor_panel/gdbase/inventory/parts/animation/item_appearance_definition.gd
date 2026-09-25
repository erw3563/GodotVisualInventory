@tool
class_name ItemAppearanceDefinition
extends Resource

@export var key: StringName
@export var texture: Texture2D
@export var loop_animation: ItemFrameAnimation

func validate_configuration() -> StringName:
	if key.is_empty():
		return &"empty_appearance_key"
	if texture != null and loop_animation != null:
		return &"ambiguous_appearance_source"
	if loop_animation != null:
		return loop_animation.validate_configuration()
	if texture == null:
		return &"missing_appearance_texture"
	return &""
