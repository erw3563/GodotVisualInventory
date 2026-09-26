@tool
@abstract
class_name ItemReactionDirectionPolicy
extends Resource
@export var local_space := true
@abstract func get_directions() -> Array[Vector2i]
func validate_configuration() -> StringName:
	var directions := get_directions()
	if directions.is_empty():
		return &"empty_movement_directions"
	for direction in directions:
		if abs(direction.x) + abs(direction.y) != 1:
			return &"invalid_movement_direction"
	return &""
