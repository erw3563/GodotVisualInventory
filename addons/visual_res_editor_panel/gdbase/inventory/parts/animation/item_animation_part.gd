@tool
class_name ItemAnimationPart
extends ItemPart
## 共享只读的静态能力；无 State，堆叠和复制继承静态 Part 语义。
@export var default_appearance_key: StringName
@export var appearances: Array[ItemAppearanceDefinition] = []
@export var animations: Array[ItemAnimationDefinition] = []

static func get_part_type() -> String:
	return "Animation"

func allows_multiple() -> bool:
	return false

func get_appearance(key: StringName) -> ItemAppearanceDefinition:
	for appearance in appearances:
		if appearance != null and appearance.key == key:
			return appearance
	return null

func get_animation(key: StringName) -> ItemAnimationDefinition:
	for animation in animations:
		if animation != null and animation.key == key:
			return animation
	return null

func validate_configuration() -> StringName:
	var keys := {}
	for appearance in appearances:
		if appearance == null:
			return &"null_appearance"
		var reason := appearance.validate_configuration()
		if not reason.is_empty():
			return reason
		if keys.has(appearance.key):
			return &"duplicate_appearance_key"
		keys[appearance.key] = true
	if not default_appearance_key.is_empty() and not keys.has(default_appearance_key):
		return &"unknown_default_appearance"
	keys.clear()
	for animation in animations:
		if animation == null:
			return &"null_animation"
		var reason := animation.validate_configuration()
		if not reason.is_empty():
			return reason
		if keys.has(animation.key):
			return &"duplicate_animation_key"
		keys[animation.key] = true
		if not animation.target_appearance_key.is_empty() and get_appearance(animation.target_appearance_key) == null:
			return &"unknown_default_appearance"
	return &""
