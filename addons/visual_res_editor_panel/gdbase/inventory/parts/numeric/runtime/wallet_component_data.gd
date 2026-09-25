class_name WalletComponentData
extends Resource
## 商店交易使用的钱包余额数据。本提取工程不依赖组件系统，仅保留金额查询与变更接口。

signal value_changed(num: int)

## 当前余额。
@export var value: int
## 币种标识。
@export var type: String = "coin"


## 判断是否能按 try_change_money 相同规则完成变更（正为入账、负为出账、零恒可）。
func able_to_change_money(money_delta: int, money_type_: String) -> bool:
	if not check_money_type(money_type_):
		return false
	if money_delta >= 0:
		return true
	return value >= absi(money_delta)


## 尝试变更余额：正数入账、负数出账；零直接成功。
func try_change_money(money_delta: int, money_type_: String) -> bool:
	if not able_to_change_money(money_delta, money_type_):
		return false
	if money_delta == 0:
		return true
	if money_delta > 0:
		value += money_delta
		value_changed.emit(value)
		return true
	value -= absi(money_delta)
	value_changed.emit(value)
	return true


## 检查币种是否与钱包一致。
func check_money_type(money_type_: String) -> bool:
	return type == money_type_
