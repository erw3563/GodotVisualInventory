extends VarMachine
class_name AssignVarMachine

## 赋给目标变量的新值。
@export var assign_value: Variant

## 初始化赋值修改器。
func init(assign_value_: Variant) -> void:
	assign_value = assign_value_

## 返回赋值结果，数组和字典会复制以避免共享引用。
func calculate(_value: Variant) -> Variant:
	return _duplicate_variant_if_needed(assign_value)

## 赋值修饰的玩家可读文本，如 "设为 999"。
func describe() -> String:
	return "设为 %s" % str(assign_value)

func _duplicate_variant_if_needed(value: Variant) -> Variant:
	if value is Array:
		return value.duplicate(true)
	if value is Dictionary:
		return value.duplicate(true)
	return value
