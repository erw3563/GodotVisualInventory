extends VarMachine
class_name ArrayVarMachine

## 数组修改器操作类型。
enum OperationType {
	APPEND,
	REMOVE,
	REPLACE,
}

## 数组运算类型。
@export var operation_type: OperationType = OperationType.APPEND
## 追加、移除或替换数组时使用的值。
@export var operand_value: Variant

## 初始化数组修改器。
func init(operation_type_: OperationType, operand_value_: Variant) -> void:
	operation_type = operation_type_
	operand_value = operand_value_

## 根据操作类型计算数组修饰结果。
func calculate(value: Variant) -> Variant:
	match operation_type:
		OperationType.APPEND:
			return _append_value(value, operand_value)
		OperationType.REMOVE:
			return _remove_value(value, operand_value)
		OperationType.REPLACE:
			return _replace_value(value, operand_value)
		_:
			push_warning("ArrayVarMachine: 未设置有效操作类型")
			return value

func _append_value(value: Variant, append_value: Variant) -> Variant:
	if value is Array:
		var next_array: Array = value.duplicate(true)
		next_array.append(append_value)
		return next_array
	push_warning("ArrayVarMachine: Append 仅支持 Array，当前类型 %s" % [typeof(value)])
	return value

func _remove_value(value: Variant, remove_value: Variant) -> Variant:
	if value is Array:
		var next_array: Array = value.duplicate(true)
		var remove_index := next_array.find(remove_value)
		if remove_index != -1:
			next_array.remove_at(remove_index)
		return next_array
	push_warning("ArrayVarMachine: Remove 仅支持 Array，当前类型 %s" % [typeof(value)])
	return value

func _replace_value(value: Variant, replace_value: Variant) -> Variant:
	if replace_value is Array:
		return replace_value.duplicate(true)
	push_warning("ArrayVarMachine: Replace 的 operand_value 必须为 Array")
	return value
