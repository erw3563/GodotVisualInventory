@tool
class_name ItemNumericEntry
extends Resource
## 一个模板数值；键稳定，显示名不参与实例对账。
enum NumberType { INTEGER, FLOAT }
enum StorageMode { FIXED, INSTANCE }
enum MergeMode { REJECT, EQUAL, WEIGHTED }
enum DisplayFormat { NUMBER, PERCENT }

@export var key: StringName = &""
@export var display_name: String = ""
@export var number_type: NumberType = NumberType.INTEGER
@export var storage_mode: StorageMode = StorageMode.FIXED
@export var value: float = 0.0
@export var initial_value: float = 0.0
@export var initialize_at_maximum: bool = false
@export var minimum_enabled: bool = false
@export var minimum: float = 0.0
@export var maximum_enabled: bool = false
@export var maximum: float = 1.0
## 修饰后的上限自身不能低于此值；与当前值的 minimum 分开。
@export var maximum_floor: float = 0.0
@export var merge_mode: MergeMode = MergeMode.EQUAL
@export var display_format: DisplayFormat = DisplayFormat.NUMBER

static func fixed(id: StringName, amount: Variant, label: String = "") -> ItemNumericEntry:
	var entry := ItemNumericEntry.new()
	entry.key = id
	entry.display_name = label
	entry.number_type = ItemNumericEntry.NumberType.INTEGER if amount is int else ItemNumericEntry.NumberType.FLOAT
	entry.value = amount
	return entry

static func bounded(id: StringName, initial: Variant, lower: Variant, upper: Variant, merge: MergeMode = MergeMode.EQUAL, fill: bool = false) -> ItemNumericEntry:
	var entry := fixed(id, initial)
	entry.storage_mode = ItemNumericEntry.StorageMode.INSTANCE
	entry.initial_value = initial
	entry.minimum_enabled = true
	entry.minimum = lower
	entry.maximum_enabled = true
	entry.maximum = upper
	entry.maximum_floor = lower
	entry.merge_mode = merge as ItemNumericEntry.MergeMode
	entry.initialize_at_maximum = fill
	return entry

func accepts_number(amount: Variant) -> bool:
	if not (amount is int or amount is float) or not is_finite(float(amount)):
		return false
	# 导出模板使用浮点控件；整数限制在可精确表示的范围，不静默丢失位数。
	return number_type == NumberType.FLOAT or (absf(float(amount)) <= 9007199254740991.0 and float(amount) == floorf(float(amount)))

func typed(amount: Variant) -> Variant:
	return int(amount) if number_type == NumberType.INTEGER else float(amount)

func validate_configuration() -> StringName:
	if String(key).strip_edges().is_empty() or String(key).contains("."):
		return &"invalid_numeric_key"
	if number_type not in NumberType.values() or storage_mode not in StorageMode.values() or merge_mode not in MergeMode.values() or display_format not in DisplayFormat.values():
		return &"invalid_numeric_mode"
	if minimum_enabled and not accepts_number(minimum) or maximum_enabled and not accepts_number(maximum):
		return &"invalid_numeric_bound"
	if minimum_enabled and maximum_enabled and minimum > maximum:
		return &"invalid_numeric_bounds"
	if maximum_enabled and (not accepts_number(maximum_floor) or maximum_floor > maximum):
		return &"invalid_numeric_maximum_floor"
	var initial := value if storage_mode == StorageMode.FIXED else initial_value
	if storage_mode == StorageMode.INSTANCE and initialize_at_maximum:
		if not maximum_enabled:
			return &"numeric_initial_maximum_missing"
		initial = maximum
	if not accepts_number(initial):
		return &"invalid_numeric_value"
	if minimum_enabled and initial < minimum or maximum_enabled and initial > maximum:
		return &"numeric_initial_out_of_bounds"
	if storage_mode == StorageMode.INSTANCE and merge_mode == MergeMode.WEIGHTED and number_type != NumberType.FLOAT:
		return &"numeric_weighted_requires_float"
	return &""

func format_value(amount: Variant) -> String:
	return "%.1f%%" % (float(amount) * 100.0) if display_format == DisplayFormat.PERCENT else str(typed(amount))

func title() -> String:
	return display_name if not display_name.is_empty() else String(key)
