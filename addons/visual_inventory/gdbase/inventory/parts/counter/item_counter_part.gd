@tool
class_name ItemCounterPart
extends ItemPart
## 独立实例计数能力；键显式填写 Counter:<语义标识>。
@export var initial_value: int = 3

static func get_part_type() -> String:
	return "Counter"

func validate_configuration() -> StringName:
	if not instance_state_key.begins_with("Counter:") or instance_state_key.trim_prefix("Counter:").strip_edges().is_empty():
		return &"invalid_counter_key"
	return &"invalid_counter_initial_value" if initial_value <= 0 else &""

func create_instance_state() -> ItemInstanceState:
	var state := ItemCounterState.new()
	# 非法模板仍声明动态状态，让通用构建器拒绝空键，不能退化为静态能力。
	state.state_key = instance_state_key if validate_configuration() == &"" else ""
	state.current_value = initial_value
	return state

func resolve_state(item: ItemInstanceData) -> ItemCounterState:
	return item.get_state_by_key(get_instance_state_key()) as ItemCounterState if item != null else null

static func find(item: ItemData, key: String) -> ItemCounterPart:
	if item == null:
		return null
	var found: ItemCounterPart
	for part in item.get_all_same_type_parts(get_part_type()):
		if part is ItemCounterPart and part.get_instance_state_key() == key:
			if found != null:
				return null
			found = part
	return found

static func validate_item(item: ItemData) -> StringName:
	if item == null:
		return &"missing_counter_item"
	var keys: Dictionary = {}
	for part in item.get_all_same_type_parts(get_part_type()):
		if not part is ItemCounterPart:
			return &"invalid_counter_part"
		var reason: StringName = part.validate_configuration()
		if reason != &"":
			return reason
		if keys.has(part.get_instance_state_key()):
			return &"duplicate_counter_key"
		keys[part.get_instance_state_key()] = true
	return &""

func get_description_panel() -> Array[Control]:
	var label := Label.new()
	label.text = "%s：初始 %d" % [instance_state_key, initial_value]
	return [label]
