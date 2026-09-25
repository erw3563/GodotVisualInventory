extends VarMachine
class_name NumberVarMachine

## 数值修改器操作类型。
enum OperationType {
	ADD,
	SUBTRACT,
	MULTIPLY,
	DIVIDE,
}

## 数值运算类型。
@export var operation_type: OperationType = OperationType.ADD
## 运算操作数，支持 int、float、Vector2、Vector2i。
@export var operand_value: Variant

## 初始化数值修改器。
func init(operation_type_: OperationType, operand_value_: Variant) -> void:
	operation_type = operation_type_
	operand_value = operand_value_

## 根据操作类型计算数值、向量修饰结果。
func calculate(value: Variant) -> Variant:
	match operation_type:
		OperationType.ADD:
			return _add_values(value, operand_value)
		OperationType.SUBTRACT:
			return _subtract_values(value, operand_value)
		OperationType.MULTIPLY:
			return _multiply_values(value, operand_value)
		OperationType.DIVIDE:
			return _divide_values(value, operand_value)
		_:
			push_warning("NumberVarMachine: 未设置有效操作类型")
			return value

## 数值运算的玩家可读文本，如 "+1"、"×2"。
func describe() -> String:
	var operand_text := str(operand_value)
	match operation_type:
		OperationType.ADD:
			return "+%s" % operand_text
		OperationType.SUBTRACT:
			return "-%s" % operand_text
		OperationType.MULTIPLY:
			return "×%s" % operand_text
		OperationType.DIVIDE:
			return "÷%s" % operand_text
	return operand_text

func _add_values(value: Variant, operand: Variant) -> Variant:
	if value is int and operand is int:
		return value + operand
	if value is float and (operand is int or operand is float):
		return value + float(operand)
	if value is Vector2 and operand is Vector2:
		return value + operand
	if value is Vector2i and operand is Vector2i:
		return value + operand
	push_warning("NumberVarMachine: Add 类型不匹配 %s + %s" % [typeof(value), typeof(operand)])
	return value

func _subtract_values(value: Variant, operand: Variant) -> Variant:
	if value is int and operand is int:
		return value - operand
	if value is float and (operand is int or operand is float):
		return value - float(operand)
	if value is Vector2 and operand is Vector2:
		return value - operand
	if value is Vector2i and operand is Vector2i:
		return value - operand
	push_warning("NumberVarMachine: Sub 类型不匹配 %s - %s" % [typeof(value), typeof(operand)])
	return value

func _multiply_values(value: Variant, operand: Variant) -> Variant:
	if value is int and (operand is int or operand is float):
		return int(round(float(value) * float(operand)))
	if value is float and (operand is int or operand is float):
		return value * float(operand)
	if value is Vector2 and (operand is int or operand is float):
		return value * float(operand)
	if value is Vector2i and operand is int:
		return value * operand
	push_warning("NumberVarMachine: Mul 类型不匹配 %s * %s" % [typeof(value), typeof(operand)])
	return value

func _divide_values(value: Variant, operand: Variant) -> Variant:
	var divisor := 0.0
	if operand is int or operand is float:
		divisor = float(operand)
	else:
		push_warning("NumberVarMachine: Div 除数类型不支持 %s" % [typeof(operand)])
		return value
	if is_zero_approx(divisor):
		push_error("NumberVarMachine: 除数不能为 0")
		return value
	if value is int:
		return int(round(float(value) / divisor))
	if value is float:
		return value / divisor
	if value is Vector2:
		return value / divisor
	if value is Vector2i:
		return Vector2i(int(round(float(value.x) / divisor)), int(round(float(value.y) / divisor)))
	push_warning("NumberVarMachine: Div 被除数类型不支持 %s" % [typeof(value)])
	return value
