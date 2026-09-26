@tool
class_name ItemNumericState
extends ModifiableItemState
## 只持有实例当前值；模板派生上下文仅为本次会话的非存储缓存。
@export_storage var values: Dictionary = {}
var _limits: Dictionary = {}

func _init() -> void:
	state_key = "Numeric"
	_connect_ledger(modifier_ledger)

func get_state_type() -> String:
	return "Numeric"

func is_valid_instance_state() -> bool:
	if state_key.is_empty():
		return false
	for key in values:
		if not (key is String or key is StringName) or String(key).is_empty():
			return false
		if not (values[key] is int or values[key] is float) or not is_finite(float(values[key])):
			return false
	return true

func effective_maximum(part: ItemNumericPart, key: StringName) -> Variant:
	var entry := part.find_entry(key) if part != null else null
	if entry == null or not entry.maximum_enabled:
		return null
	return _maximum(entry)

func _maximum(entry: ItemNumericEntry) -> Variant:
	var result: Variant = calculate_effective_value(StringName(String(entry.key) + ".max"), entry.typed(entry.maximum))
	if not entry.accepts_number(result):
		return null
	result = max(result, entry.typed(entry.maximum_floor))
	if entry.minimum_enabled:
		result = max(result, entry.typed(entry.minimum))
	return entry.typed(result)

func _bounded(entry: ItemNumericEntry, amount: Variant) -> Variant:
	if not entry.accepts_number(amount):
		return null
	var result: Variant = entry.typed(amount)
	if entry.minimum_enabled:
		result = max(result, entry.typed(entry.minimum))
	if entry.maximum_enabled:
		var upper: Variant = _maximum(entry)
		if upper == null:
			return null
		result = min(result, upper)
	return entry.typed(result)

func reconcile_with_part(part: ItemPart) -> bool:
	var numeric := part as ItemNumericPart
	if numeric == null or numeric.validate_configuration() != &"" or not is_valid_instance_state():
		return false
	for modifier in modifier_ledger.modifiers + modifier_ledger.get_runtime_modifiers():
		if modifier == null:
			return false
	var next := {}
	var limits := {}
	for entry in numeric.entries:
		if entry.storage_mode != ItemNumericEntry.StorageMode.INSTANCE:
			continue
		var amount: Variant
		if values.has(entry.key):
			amount = values[entry.key]
			if typeof(amount) != (TYPE_INT if entry.number_type == ItemNumericEntry.NumberType.INTEGER else TYPE_FLOAT):
				return false
		else:
			amount = _maximum(entry) if entry.initialize_at_maximum else entry.typed(entry.initial_value)
		var bounded: Variant = _bounded(entry, amount)
		if bounded == null:
			return false
		next[entry.key] = bounded
		limits[entry.key] = entry.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	values = next
	_limits = limits
	# 删除条目同时移除其账本项，防止以后同键新条目继承旧修饰。
	var all := modifier_ledger.modifiers + modifier_ledger.get_runtime_modifiers()
	for modifier in all:
		if not supports_value_key(StringName(modifier.modifier_property_name)):
			modifier_ledger.remove_modifier(modifier)
	return true

func supports_value_key(value_key: StringName) -> bool:
	var text := String(value_key)
	if not text.ends_with(".max"):
		return false
	var key := StringName(text.trim_suffix(".max"))
	return _limits.has(key) and _limits[key].maximum_enabled

func add_value_modifier(value_key: StringName, modifier: Modifier, persistent: bool = true) -> bool:
	if not supports_value_key(value_key) or modifier == null or modifier.machine == null:
		return false
	var entry: ItemNumericEntry = _limits[StringName(String(value_key).trim_suffix(".max"))]
	var prospective := modifier_ledger.modifiers + modifier_ledger.get_runtime_modifiers()
	prospective.append(modifier)
	var calculated: Variant = ModifierCalculator.calculate(entry.typed(entry.maximum), value_key, prospective)
	if not entry.accepts_number(calculated):
		return false
	return super.add_value_modifier(value_key, modifier, persistent)

func _on_modifier_ledger_changed(value_key: StringName) -> void:
	var key := StringName(String(value_key).trim_suffix(".max"))
	if not _limits.has(key) or not values.has(key):
		return
	var bounded: Variant = _bounded(_limits[key], values[key])
	if bounded != null:
		values[key] = bounded

func duplicate_state() -> ItemInstanceState:
	var result := super.duplicate_state() as ItemNumericState
	result._limits = _limits.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	return result

## 同一物品事务更新保留修饰身份和临时账本，不使用“新独立物品”的复制语义。
func duplicate_for_operation() -> ItemInstanceState:
	var result := super.duplicate_for_operation() as ItemNumericState
	result._limits = _limits.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	return result

func plan_stack_merge(context: ItemStackMergeContext) -> ItemStateMergePlan:
	var part := context.target_part as ItemNumericPart
	var other := context.source_state as ItemNumericState
	if part == null or context.source_part != part or other == null or part.validate_configuration() != &"":
		return ItemStateMergePlan.reject(&"numeric_stack_mismatch")
	var ours := [modifier_ledger.modifiers, modifier_ledger.get_runtime_modifiers()]
	var theirs := [other.modifier_ledger.modifiers, other.modifier_ledger.get_runtime_modifiers()]
	if InventoryOperationFingerprint.of(ours) != InventoryOperationFingerprint.of(theirs):
		return ItemStateMergePlan.reject(&"numeric_modifiers_differ")
	# 临时修饰的生命周期归消费者；无法独立复制其租约时关闭合并。
	if not modifier_ledger.get_runtime_modifiers().is_empty():
		return ItemStateMergePlan.reject(&"numeric_runtime_modifier_merge_disabled")
	var result := duplicate_state() as ItemNumericState
	for entry in part.entries:
		if entry.storage_mode != ItemNumericEntry.StorageMode.INSTANCE:
			continue
		if not values.has(entry.key) or not other.values.has(entry.key):
			return ItemStateMergePlan.reject(&"numeric_value_missing")
		var left: Variant = values[entry.key]
		var right: Variant = other.values[entry.key]
		var expected_type := TYPE_INT if entry.number_type == ItemNumericEntry.NumberType.INTEGER else TYPE_FLOAT
		if typeof(left) != expected_type or typeof(right) != expected_type or not entry.accepts_number(left) or not entry.accepts_number(right):
			return ItemStateMergePlan.reject(&"invalid_numeric_value")
		match entry.merge_mode:
			ItemNumericEntry.MergeMode.REJECT:
				return ItemStateMergePlan.reject(&"numeric_stack_merge_disabled")
			ItemNumericEntry.MergeMode.EQUAL:
				if left != right:
					return ItemStateMergePlan.reject(&"numeric_values_differ")
			ItemNumericEntry.MergeMode.WEIGHTED:
				result.values[entry.key] = (float(left) * context.target_num + float(right) * context.transfer_num) / float(context.target_num + context.transfer_num)
			_:
				return ItemStateMergePlan.reject(&"invalid_numeric_merge_mode")
	if not result.reconcile_with_part(part):
		return ItemStateMergePlan.reject(&"invalid_numeric_state")
	return ItemStateMergePlan.accept(result, other.duplicate_state() if context.source_num > context.transfer_num else null)

func get_description_panel_with_part(part: ItemPart) -> Array[Control]:
	var numeric := part as ItemNumericPart
	var result: Array[Control] = []
	if numeric == null or numeric.validate_configuration() != &"":
		return result
	for entry in numeric.entries:
		var label := Label.new()
		if entry.storage_mode == ItemNumericEntry.StorageMode.FIXED:
			label.text = entry.title() + "：" + entry.format_value(entry.value)
		elif values.has(entry.key):
			label.text = entry.title() + "：" + entry.format_value(values[entry.key])
			if entry.maximum_enabled and entry.display_format != ItemNumericEntry.DisplayFormat.PERCENT:
				var upper: Variant = effective_maximum(numeric, entry.key)
				if upper != null:
					label.text += " / " + entry.format_value(upper)
		else:
			label.text = entry.title() + "：缺少实例数值"
		result.append(label)
		for modifier in get_value_modifiers(StringName(String(entry.key) + ".max")):
			if modifier != null and modifier.machine != null:
				var note := Label.new()
				note.text = modifier.modifier_name + "：" + modifier.machine.describe()
				result.append(note)
	return result
