class_name ShopInteractionCostCalculator
extends RefCounted
## 商店交互花费计算器：根据物品数据与倍率计算拿取/放入花费，并校验交易上下文。
## 倍率与货币类型可由 ShopTradePolicy / ShopTradeSession 在交易前同步。

## 拿取时使用的倍率（与基础价相乘）。正值表示玩家支付对应花费。
var take_item_cost_multiplier: float = 1.0
## 放入时倍率；为正表示玩家扣款，为负表示向玩家付款（回收/卖出）。
var put_item_cost_multiplier: float = -0.5
## 旋转物品时每 90° 一步相对基础价的费用倍率。
var rotate_item_cost_multiplier: float = 1.0
## 默认货币类型，用于从物品中筛选对应数值条目。
var money_type: String = "coin"

## 创建计算器并设置交互倍率。
func _init(take_multiplier: float = 1.0, put_multiplier: float = -0.5, target_money_type: String = "coin") -> void:
	take_item_cost_multiplier = take_multiplier
	put_item_cost_multiplier = put_multiplier
	money_type = target_money_type


## 从交易策略同步倍率与货币类型。
func apply_from_policy(trade_policy: ShopTradePolicy) -> void:
	if trade_policy == null:
		return
	take_item_cost_multiplier = trade_policy.take_item_cost_multiplier
	put_item_cost_multiplier = trade_policy.put_item_cost_multiplier
	rotate_item_cost_multiplier = trade_policy.rotate_item_cost_multiplier
	money_type = trade_policy.money_type

## 计算拿取指定物品数量的总花费。
func calculate_take_item_cost(item_data: ItemData, amount: int = 1) -> int:
	return calculate_item_interaction_cost(item_data, amount, take_item_cost_multiplier)

## 计算放入指定物品数量的总花费。
func calculate_put_item_cost(item_data: ItemData, amount: int = 1) -> int:
	return calculate_item_interaction_cost(item_data, amount, put_item_cost_multiplier)

## 计算指定交互倍率下的总花费。
func calculate_item_interaction_cost(item_data: ItemData, amount: int, interaction_cost_multiplier: float) -> int:
	if item_data == null:
		return 0
	if amount <= 0:
		return 0

	var base_price := get_item_base_price(item_data)
	if base_price <= 0:
		return 0

	return roundi(float(base_price * amount) * interaction_cost_multiplier)

## 获取物品在当前货币类型下的基础单价。
func get_item_base_price(item_data: ItemData) -> int:
	return ItemPriceQuery.get_base_price(item_data, StringName(money_type))


## 获取当前币种；只有有效的正整数固定单价才返回币种。
func get_item_money_type(item_data: ItemData) -> String:
	return money_type if get_item_base_price(item_data) > 0 else ""

## 单件物品按拿取倍率折算的应付金额绝对值（无有效价格条目时为 0）。
func get_take_item_unit_cost_absolute(item_data: ItemData) -> int:
	var base_price := get_item_base_price(item_data)
	return absi(roundi(float(base_price) * take_item_cost_multiplier))

## 单件物品按放入倍率折算的金额绝对值（无有效价格条目时为 0）。
func get_put_item_unit_cost_absolute(item_data: ItemData) -> int:
	var base_price := get_item_base_price(item_data)
	return absi(roundi(float(base_price) * put_item_cost_multiplier))

## 校验商店交易上下文是否完整且可用。
func has_valid_shop_trade_context(
	item_instance: ItemInstanceData,
	customer_wallet: WalletComponentData
) -> bool:
	if item_instance == null:
		push_warning("ShopInteractionCostCalculator：交易失败，item_instance 为空。")
		return false
	if customer_wallet == null:
		push_warning("ShopInteractionCostCalculator：交易失败，未配置 customer_wallet。")
		return false
	var item_data := item_instance.get_item_data()
	if item_data == null:
		push_warning("ShopInteractionCostCalculator：交易失败，item_data 为空。")
		return false
	if get_item_base_price(item_data) <= 0:
		return false
	var trade_money_type := get_item_money_type(item_data)
	if trade_money_type == "":
		push_warning("ShopInteractionCostCalculator：交易失败，物品未配置货币类型。物品：%s" % [item_instance.get_item_name()])
		return false
	if trade_money_type != money_type:
		push_warning("ShopInteractionCostCalculator：交易失败，物品货币类型与商店货币类型不一致。物品：%s" % [item_instance.get_item_name()])
		return false
	if !customer_wallet.check_money_type(trade_money_type):
		push_warning("ShopInteractionCostCalculator：交易失败，钱包货币类型不匹配。")
		return false
	return true

## 拿取路径：与钱包对齐的带符号金额（负为玩家支出，正为玩家收入）。
func get_take_transaction_signed_for_wallet(item_data: ItemData, amount: int) -> int:
	var raw := roundi(float(get_item_base_price(item_data)) * float(amount) * take_item_cost_multiplier)
	return -raw

## 放入路径：与钱包对齐的带符号金额（负为玩家支出，正为玩家收入）。倍率为正时与拿取一致，均为向玩家扣款。
func get_put_transaction_signed_for_wallet(item_data: ItemData, amount: int) -> int:
	var raw := roundi(float(get_item_base_price(item_data)) * float(amount) * put_item_cost_multiplier)
	return -raw

## 旋转路径：与钱包对齐的带符号金额（通常为负，表示玩家支出）。按 90° 步数累计，步数为 rotate_step 的绝对值。
func get_rotate_transaction_signed_for_wallet(item_data: ItemData, rotate_step: int) -> int:
	var quarter_turns := absi(rotate_step)
	if quarter_turns == 0:
		return 0
	var raw := roundi(
		float(get_item_base_price(item_data)) * float(quarter_turns) * rotate_item_cost_multiplier
	)
	return -raw

## 本次旋转应付金额绝对值（基础价×旋转倍率×90° 步数）。
func get_rotate_cost_absolute(item_data: ItemData, rotate_step: int) -> int:
	return absi(get_rotate_transaction_signed_for_wallet(item_data, rotate_step))

## 判断当前旋转扣款是否允许（花费为 0 时不校验完整交易上下文）。
func can_apply_rotate_money(
	item_instance: ItemInstanceData,
	rotate_step: int,
	customer_wallet: WalletComponentData
) -> bool:
	var signed := get_rotate_transaction_signed_for_wallet(item_instance.get_item_data(), rotate_step)
	if signed == 0:
		return true
	if !has_valid_shop_trade_context(item_instance, customer_wallet):
		return false
	var trade_money_type := get_item_money_type(item_instance.get_item_data())
	return customer_wallet.able_to_change_money(signed, trade_money_type)

## 检查交易上下文与金额是否允许执行；金额为 0 时视为免费放行（不校验完整交易上下文）。
func can_apply_trade_money(
	item_instance: ItemInstanceData,
	amount: int,
	transaction_signed: int,
	customer_wallet: WalletComponentData
) -> bool:
	if amount <= 0:
		return false
	if transaction_signed == 0:
		return true
	if !has_valid_shop_trade_context(item_instance, customer_wallet):
		return false
	var trade_money_type := get_item_money_type(item_instance.get_item_data())
	return customer_wallet.able_to_change_money(transaction_signed, trade_money_type)
