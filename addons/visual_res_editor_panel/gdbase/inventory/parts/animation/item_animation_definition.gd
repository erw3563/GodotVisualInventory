@tool
class_name ItemAnimationDefinition
extends Resource

@export var key: StringName
@export var content: ItemAnimationContent
@export var target_appearance_key: StringName

func validate_configuration() -> StringName:
	if key.is_empty():
		return &"empty_animation_key"
	if content == null:
		return &"missing_animation_content"
	return content.validate_configuration()
