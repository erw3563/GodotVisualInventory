@tool
class_name ItemNumericPart
extends ItemPart
## 一组数值模板；仅实例模式条目进入 State。
const PART_TYPE := "Numeric"
const STATE_KEY := "Numeric"
@export var entries: Array[ItemNumericEntry] = []

static func from_entries(values: Array[ItemNumericEntry]) -> ItemNumericPart:
	var part := ItemNumericPart.new()
	part.entries = values
	return part

static func get_part_type() -> String:
	return PART_TYPE

func allows_multiple() -> bool:
	return false

func get_instance_state_key() -> String:
	return instance_state_key if not instance_state_key.is_empty() else STATE_KEY

func find_entry(key: StringName) -> ItemNumericEntry:
	for entry in entries:
		if entry != null and entry.key == key:
			return entry
	return null

func validate_configuration() -> StringName:
	var seen := {}
	for entry in entries:
		if entry == null:
			return &"null_numeric_entry"
		var reason := entry.validate_configuration()
		if reason != &"":
			return reason
		if seen.has(entry.key):
			return &"duplicate_numeric_key"
		seen[entry.key] = true
	return &""

func create_instance_state() -> ItemInstanceState:
	var state := ItemNumericState.new()
	if validate_configuration() != &"":
		# 非法静态配置也必须让通用 Builder 失败。
		state.state_key = ""
		return state
	var has_dynamic := false
	for entry in entries:
		has_dynamic = has_dynamic or entry.storage_mode == ItemNumericEntry.StorageMode.INSTANCE
	if not has_dynamic:
		return null
	state.state_key = get_instance_state_key()
	if not state.reconcile_with_part(self):
		state.state_key = ""
	return state

func resolve_state(item: ItemInstanceData) -> ItemNumericState:
	return item.peek_state_by_key(get_instance_state_key()) as ItemNumericState if item != null else null

func get_description_panel() -> Array[Control]:
	var result: Array[Control] = []
	if validate_configuration() != &"":
		return result
	for entry in entries:
		var label := Label.new()
		var initial := entry.value if entry.storage_mode == ItemNumericEntry.StorageMode.FIXED else (entry.maximum if entry.initialize_at_maximum else entry.initial_value)
		label.text = entry.title() + "：" + entry.format_value(initial)
		result.append(label)
	return result
