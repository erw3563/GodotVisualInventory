@tool
class_name ItemReactionRandomOutput
extends ItemReactionOutputSource
@export var entries: Array[ItemReactionOutputEntry] = []
@export_range(1, 128, 1) var draws := 1
func validate_configuration() -> StringName:
	if draws <= 0 or draws > 128:
		return &"invalid_output_draws"
	var total := 0.0
	for entry in entries:
		if entry == null or entry.validate_configuration() != &"":
			return &"invalid_output_entry"
		total += entry.weight
	return &"" if total > 0 and is_finite(total) else &"empty_random_pool"
func sample(context: ItemReactionPlanContext) -> Array[ItemReactionOutputEntry]:
	var result: Array[ItemReactionOutputEntry] = []
	var total := 0.0
	var fallback: ItemReactionOutputEntry
	for entry in entries:
		total += entry.weight
		if entry.weight > 0:
			fallback = entry
	for index in draws:
		var roll := context.random.randf() * total
		var chosen := fallback
		for entry in entries:
			if entry.weight <= 0:
				continue
			roll -= entry.weight
			if roll < 0:
				chosen = entry
				break
		result.append(chosen)
	return result
