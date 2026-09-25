extends VarMachine
class_name DictionaryVarMachine

## 字典修改器操作类型。
enum OperationType {
	SET,
	REMOVE,
	REPLACE,
}

## 字典运算类型。
@export var operation_type: OperationType = OperationType.SET
## 设置或删除字典项时使用的键。
@export var container_key: Variant
## 设置字典项或替换字典时使用的值。
@export var operand_value: Variant

## 初始化字典修改器。
func init(operation_type_: OperationType, operand_value_: Variant, container_key_: Variant = null) -> void:
	operation_type = operation_type_
	operand_value = operand_value_
	container_key = container_key_

## 根据操作类型计算字典修饰结果。
func calculate(value: Variant) -> Variant:
	match operation_type:
		OperationType.SET:
			return _set_value(value, container_key, operand_value)
		OperationType.REMOVE:
			return _remove_value(value, container_key)
		OperationType.REPLACE:
			return _replace_value(value, operand_value)
		_:
			push_warning("DictionaryVarMachine: 未设置有效操作类型")
			return value

func _set_value(value: Variant, key: Variant, dictionary_value: Variant) -> Variant:
	if value is Dictionary:
		var next_dictionary: Dictionary = value.duplicate(true)
		next_dictionary[key] = dictionary_value
		return next_dictionary
	push_warning("DictionaryVarMachine: Set 仅支持 Dictionary，当前类型 %s" % [typeof(value)])
	return value

func _remove_value(value: Variant, key: Variant) -> Variant:
	if value is Dictionary:
		var next_dictionary: Dictionary = value.duplicate(true)
		next_dictionary.erase(key)
		return next_dictionary
	push_warning("DictionaryVarMachine: Remove 仅支持 Dictionary，当前类型 %s" % [typeof(value)])
	return value

func _replace_value(value: Variant, replace_value: Variant) -> Variant:
	if replace_value is Dictionary:
		return replace_value.duplicate(true)
	push_warning("DictionaryVarMachine: Replace 的 operand_value 必须为 Dictionary")
	return value
