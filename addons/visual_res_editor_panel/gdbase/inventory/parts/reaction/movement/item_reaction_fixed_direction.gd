@tool
class_name ItemReactionFixedDirection
extends ItemReactionDirectionPolicy
@export var direction := Vector2i.RIGHT
func get_directions() -> Array[Vector2i]:
	return [direction]
