class_name ShopTradePolicy
extends Resource
## 商店交易策略：货币类型、拿取/放入/旋转倍率，以及各路径是否启用结算。

## 商店使用的货币类型（需与物品固定整数数值键、钱包一致）。
@export var money_type: String = "coin"
## 从货架取出时的价格倍率（相对基础价）。正值表示玩家付钱。
@export var take_item_cost_multiplier: float = 1.0
## 放入货架时的价格倍率。负值表示商店向玩家付款（卖出）。
@export var put_item_cost_multiplier: float = -0.5
## 旋转货架内物品时每 90° 一步的费用倍率。
@export var rotate_item_cost_multiplier: float = 1.0
## 为 false 时取出不结算（免费取出）。
@export var take_trade_enabled: bool = true
## 为 false 时放入不结算（免费入库）。
@export var put_trade_enabled: bool = true
## 为 false 时旋转不结算。
@export var rotate_trade_enabled: bool = true


## 商人货架：取出买入、放入卖出。
static func make_merchant_shelf() -> ShopTradePolicy:
	var policy := ShopTradePolicy.new()
	policy.money_type = "coin"
	policy.take_item_cost_multiplier = 1.0
	policy.put_item_cost_multiplier = -0.5
	policy.rotate_item_cost_multiplier = 1.0
	policy.take_trade_enabled = true
	policy.put_trade_enabled = true
	policy.rotate_trade_enabled = true
	return policy
