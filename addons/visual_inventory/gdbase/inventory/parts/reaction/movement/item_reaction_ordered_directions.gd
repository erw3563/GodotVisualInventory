@tool
class_name ItemReactionOrderedDirections
extends ItemReactionDirectionPolicy
@export var directions: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
func get_directions() -> Array[Vector2i]:
	return directions.duplicate()
