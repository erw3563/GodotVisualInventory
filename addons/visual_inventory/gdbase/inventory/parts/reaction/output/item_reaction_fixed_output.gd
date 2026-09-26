@tool
class_name ItemReactionFixedOutput
extends ItemReactionOutputSource
@export var entries: Array[ItemReactionOutputEntry] = []
func validate_configuration() -> StringName:
	if entries.is_empty():
		return &"empty_output"
	for entry in entries:
		if entry == null or entry.validate_configuration() != &"":
			return &"invalid_output_entry"
	return &""
func sample(_context: ItemReactionPlanContext) -> Array[ItemReactionOutputEntry]:
	return entries.duplicate()
