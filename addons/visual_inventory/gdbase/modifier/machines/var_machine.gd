@abstract
extends Resource
class_name VarMachine

## 计算变量修饰结果，具体规则由子类实现。
func calculate(value: Variant) -> Variant:
	push_warning("VarMachine: 子类需要覆写 calculate 方法")
	return value

## 返回修饰强度的玩家可读文本；子类覆写。
func describe() -> String:
	return ""
