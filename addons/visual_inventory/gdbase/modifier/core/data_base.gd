@abstract
extends Resource
class_name DataBase
## 属性修饰内核：以"基准值快照 + 全量重算"维护被修饰属性。
##
## 基准值契约（违反会静默丢数据）：
## 1. 属性被修饰期间禁止直接赋值（如 data.max_hp = 99）——重算总是从基准快照出发，直写值会被丢弃。
## 2. 修饰存续期间需要修改基准值时，必须走 set_base_value()。
## 3. modifiers 与 base_values 用 @export_storage 序列化，保证深拷贝/存档往返后"值与账本"一致；
##    跨拷贝重挂时运行时按 origin_id 认领同血统修饰，不会双重生效。

## 已挂载的属性修饰，键为逻辑名，便于移除modifier；
@export_storage
var modifiers: Array[Modifier] = []
## 基准值缓存。键为属性名，值为首次应用持续修饰前的基础值快照。
@export_storage
var base_values:Dictionary[StringName, Variant] = {}

## 添加修饰
func add_modifier(modifier: Modifier) -> void:
	if !modifier:
		return
	if !_can_register_modifier(modifier):
		return
	modifiers.append(modifier)
	_ensure_base_value_cached(modifier.modifier_property_name)
	recalculate_property(modifier.modifier_property_name)

## 仅移除同一 Modifier 实例的持续修饰行为。
func remove_modifier(modifier: Modifier) -> void:
	if !modifiers.has(modifier):
		return
	var target_property_name := modifier.modifier_property_name
	modifiers.erase(modifier)
	if _has_modifier_on_property(target_property_name):
		recalculate_property(target_property_name)
	else:
		_restore_property_from_base_cache(target_property_name)

## 修饰存续期间安全修改基准值；无修饰缓存时等价于直接赋值。
func set_base_value(property_name: StringName, value: Variant) -> void:
	if !_has_property_name(property_name):
		push_warning("DataBase: 不存在属性 %s" % property_name)
		return
	if base_values.has(property_name):
		base_values[property_name] = _duplicate_variant_if_needed(value)
		recalculate_property(property_name)
	else:
		set(property_name, _duplicate_variant_if_needed(value))

## 检测修饰是否允许注册。
func _can_register_modifier(modifier: Modifier) -> bool:
	return ModifierCalculator.can_register(modifiers, modifier, "DataBase")

## 重新计算指定属性
func recalculate_property(property_name:String) -> void:
	if property_name.is_empty():
		return
	if !_has_property_name(property_name):
		push_warning("DataBase: 不存在属性 %s" % property_name)
		return
	_ensure_base_value_cached(property_name)
	var value: Variant = ModifierCalculator.calculate(
		base_values[property_name],
		StringName(property_name),
		modifiers
	)
	set(property_name, value)

## 按 phase_priority 进行稳定排序（相同优先级保持原顺序）。
func sort_modifiers(a:Modifier,b:Modifier) -> bool:
	if a.phase_priority != b.phase_priority:
		return a.phase_priority > b.phase_priority
	var order_index_a := _get_modifier_order_index(a)
	var order_index_b := _get_modifier_order_index(b)
	return order_index_a < order_index_b

## 获取修饰在 _modifier_order 中的顺序索引。
func _get_modifier_order_index(target_modifier: Modifier) -> int:
	var order_index := modifiers.find(target_modifier)
	if order_index == -1:
		return modifiers.size()
	return order_index

## 重新计算所有被修饰的属性。
func recalculate_all_modified_properties() -> void:
	var touched_properties:Dictionary[String, bool] = {}
	for modifier in modifiers:
		touched_properties[modifier.modifier_property_name] = true
	for property_name in touched_properties.keys():
		recalculate_property(property_name)

## 获取拥有的适用于该属性的修改
func _get_modifier_entries_for_property(property_name:String) -> Array[Modifier]:
	var entries:Array[Modifier] = []
	for modifier in modifiers:
		if modifier.modifier_property_name != property_name:
			continue
		entries.append(modifier)
	return entries

## 判断输入的属性是否已经有基础值缓存，如果没有则将当前值缓存为属性的基础值
func _ensure_base_value_cached(property_name:StringName) -> void:
	if base_values.has(property_name):
		return
	if !_has_property_name(property_name):
		return
	base_values[property_name] = _duplicate_variant_if_needed(get(property_name))

## 该属性是否有修饰
func _has_modifier_on_property(property_name:StringName) -> bool:
	for modifier in modifiers:
		if modifier.modifier_property_name == property_name:
			return true
	return false

## 将属性重新设置为基础值
func _restore_property_from_base_cache(property_name:StringName) -> void:
	if !base_values.has(property_name):
		return
	if !_has_property_name(property_name):
		base_values.erase(property_name)
		return
	set(property_name, _duplicate_variant_if_needed(base_values[property_name]))
	base_values.erase(property_name)

## 判断该属性是否存在
func _has_property_name(property_name: StringName) -> bool:
	for property in get_property_list():
		if property.name == property_name:
			return true
	return false

func _duplicate_variant_if_needed(value:Variant) -> Variant:
	if value is Array:
		return value.duplicate(true)
	if value is Dictionary:
		return value.duplicate(true)
	return value
