@tool
extends RefCounted
## 为 Inspector 提供功能配置与添加声明。
func describe() -> Dictionary:
	return {"type": ShopTradeRulesFeatureDefinition, "title": "交易规则", "description": "归属：ItemNumericPart\n用途：为同 Host 的消费功能提供交易会话、策略与钱包绑定。\n装配影响：为每个 Host 创建一份交易会话节点，并在换绑时绑定钱包与策略。\n生效方式：装配与换绑时刷新会话；消费功能在输入时读取本会话完成结算。\n外部依赖：由场景组装方注入商店库存绑定；消费拿取、放置、旋转、转移须另行添加并排在本功能之后。", "category": "物品能力", "keywords": "交易 钱包 单件 整组"}

func build(form: Control) -> void:
	form.labels.merge({"money_type": "货币类型", "take_item_cost_multiplier": "取出价格倍率", "put_item_cost_multiplier": "放入价格倍率", "rotate_item_cost_multiplier": "旋转价格倍率", "take_trade_enabled": "取出结算", "put_trade_enabled": "放入结算", "rotate_trade_enabled": "旋转结算"})
	form.add_field("trade_policy", "交易策略")
	form.add_note("空策略使用标准商人货架。运行时注入 ShopInventoryBinding。")

func diagnose(_feature: InventoryHostFeatureDefinition, _layout: Resource, _features: Array[InventoryHostFeatureDefinition]) -> Array[Dictionary]:
	return [{"note": "钱包由运行时绑定注入。"}]
