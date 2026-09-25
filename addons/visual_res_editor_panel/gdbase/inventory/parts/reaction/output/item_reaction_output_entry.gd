@tool
class_name ItemReactionOutputEntry
extends Resource
@export var item_data: ItemData
@export_range(1, 100000, 1) var quantity := 1
@export var weight := 1.0
func validate_configuration() -> StringName:
	if item_data == null or quantity <= 0 or weight < 0 or not is_finite(weight):
		return &"invalid_output_entry"
	return &""
