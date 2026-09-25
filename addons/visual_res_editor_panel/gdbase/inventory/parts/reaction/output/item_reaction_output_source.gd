@tool
@abstract
class_name ItemReactionOutputSource
extends Resource
@abstract func validate_configuration() -> StringName
@abstract func sample(context: ItemReactionPlanContext) -> Array[ItemReactionOutputEntry]
