class_name ModifierCalculator
extends RefCounted
## 无状态 Modifier 运算器。每次以调用方提供的基础值完整重算，不缓存目标或结果。

## 按逻辑属性过滤修饰，并按 phase_priority 降序、登记顺序稳定执行。
static func calculate(
	base_value: Variant,
	property_name: StringName,
	modifiers: Array[Modifier]
) -> Variant:
	var value: Variant = duplicate_variant_if_needed(base_value)
	if property_name == StringName():
		return value
	for modifier in _ordered_modifiers(property_name, modifiers):
		value = modifier.calculate_forward(value)
	return value

## 复制可变容器，避免空修饰或计算失败时把调用方基础值暴露给后续写入。
static func duplicate_variant_if_needed(value: Variant) -> Variant:
	if value is Array:
		return value.duplicate(true)
	if value is Dictionary:
		return value.duplicate(true)
	return value

## 通用登记合法性，供缓存型 DataBase 与实时基础值 Ledger 共同使用。
static func can_register(
	existing_modifiers: Array[Modifier],
	modifier: Modifier,
	context_label: String = "Modifier"
) -> bool:
	if modifier == null:
		return false
	if existing_modifiers.has(modifier):
		push_warning("%s: 同一 Modifier 实例只能添加一次" % context_label)
		return false
	if modifier.is_stackable:
		return true
	for old_modifier: Modifier in existing_modifiers:
		if old_modifier == null or old_modifier.modifier_name != modifier.modifier_name:
			continue
		push_error("%s: 属性 %s 上已有不可堆叠修饰" % [
			context_label,
			str(modifier.modifier_name),
		])
		return false
	return true

## 使用插入排序显式保持相同优先级的登记顺序。
static func _ordered_modifiers(
	property_name: StringName,
	modifiers: Array[Modifier]
) -> Array[Modifier]:
	var ordered: Array[Modifier] = []
	for modifier in modifiers:
		if modifier == null:
			continue
		if StringName(modifier.modifier_property_name) != property_name:
			continue
		var insert_index := ordered.size()
		for index in ordered.size():
			if modifier.phase_priority > ordered[index].phase_priority:
				insert_index = index
				break
		ordered.insert(insert_index, modifier)
	return ordered
