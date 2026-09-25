class_name ModifierLedger
extends Resource
## 可序列化的实例修饰账本。基础值由调用方实时传入，账本不缓存模板快照。

signal ledger_changed(property_name: StringName)

@export_storage var modifiers: Array[Modifier] = []
var _runtime_modifiers: Array[Modifier] = []

## 只读快照视图；不改变普通资源保存和独立物品复制的临时修饰语义。
func get_runtime_modifiers() -> Array[Modifier]:
	return _runtime_modifiers.duplicate()

## 添加修饰；同实例、同血统或不可堆叠冲突均保持原账本。
func add_modifier(modifier: Modifier, persistent: bool = true) -> bool:
	if modifier == null:
		return false
	if find_same_lineage(modifier) != null:
		return false
	var all_modifiers := _all_modifiers()
	if !ModifierCalculator.can_register(all_modifiers, modifier, "ModifierLedger"):
		return false
	if persistent:
		modifiers.append(modifier)
	else:
		_runtime_modifiers.append(modifier)
	ledger_changed.emit(StringName(modifier.modifier_property_name))
	emit_changed()
	return true

## 按同实例或同血统移除实际挂载项。
func remove_modifier(modifier: Modifier) -> bool:
	var mounted := find_same_lineage(modifier)
	if mounted == null:
		return false
	var property_name := StringName(mounted.modifier_property_name)
	modifiers.erase(mounted)
	_runtime_modifiers.erase(mounted)
	ledger_changed.emit(property_name)
	emit_changed()
	return true

## 以当前外部基础值计算有效值。
func calculate(property_name: StringName, base_value: Variant) -> Variant:
	return ModifierCalculator.calculate(base_value, property_name, _all_modifiers())

## 查找同实例或同血统的实际账本项。
func find_same_lineage(modifier: Modifier) -> Modifier:
	if modifier == null:
		return null
	for existing in _all_modifiers():
		if existing != null and existing.is_same_lineage(modifier):
			return existing
	return null

## 返回指定逻辑属性的修饰副本数组（Modifier 本体不复制）。
func get_modifiers_for(property_name: StringName) -> Array[Modifier]:
	var result: Array[Modifier] = []
	for modifier in _all_modifiers():
		if modifier != null and StringName(modifier.modifier_property_name) == property_name:
			result.append(modifier)
	return result

## 指定逻辑属性是否有修饰。
func has_modifiers_for(property_name: StringName) -> bool:
	return !get_modifiers_for(property_name).is_empty()

func _all_modifiers() -> Array[Modifier]:
	var result: Array[Modifier] = []
	result.append_array(modifiers)
	result.append_array(_runtime_modifiers)
	return result
