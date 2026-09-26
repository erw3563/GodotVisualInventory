@tool
extends RefCounted
## 为 Inspector 提供功能配置与添加声明。
func describe() -> Dictionary:
	return {"required_features": [{"type": ShopTradeRulesFeatureDefinition, "before": true}], "type": ShopTakeFeatureDefinition, "title": "消费拿取", "description": "归属：ItemNumericPart\n用途：按取出策略从货架拿取单件或整组物品，并结算钱包。\n装配影响：为每个 Host 创建消费拿取处理器，并绑定本 Host 交易会话。\n生效方式：收到拿取输入时结算；失败保持库存与钱包不变。\n外部依赖：编辑器自动添加交易规则并要求排在本功能之前；顾客钱包由场景组装方注入。", "category": "交互", "keywords": "交易 钱包 单件 整组"}

func build(form: Control) -> void:
	form.add_input_actions([InventoryInputActionIds.PRIMARY, InventoryInputActionIds.PRIMARY_SINGLE])
	form.add_input_priority()
	form.add_note("费用可为扣款、收入或免费，取决于交易策略。")

func diagnose(_feature: InventoryHostFeatureDefinition, _layout: Resource, _features: Array[InventoryHostFeatureDefinition]) -> Array[Dictionary]:
	return [{"note": "钱包由运行时绑定注入。"}]
