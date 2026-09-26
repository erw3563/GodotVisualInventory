@tool
extends RefCounted
## 为 Inspector 提供功能配置与添加声明。
func describe() -> Dictionary:
	return {"required_features": [{"type": ShopTradeRulesFeatureDefinition, "before": true}], "type": ShopTransferFeatureDefinition, "title": "消费转移", "description": "归属：ItemNumericPart\n用途：在两端 Host 之间转移物品，并按拿出与放入策略结算钱包。\n装配影响：为每个 Host 创建消费转移贡献与快捷转移处理器。\n生效方式：收到快捷转移输入时，经转移中心收集两端贡献并结算。\n外部依赖：编辑器自动添加交易规则并要求排在本功能之前；对端需要转移功能；顾客钱包由场景组装方注入。", "category": "交互", "keywords": "交易 钱包 单件 整组"}

func build(form: Control) -> void:
	form.add_input_actions([InventoryInputActionIds.QUICK_TRANSFER, InventoryInputActionIds.QUICK_TRANSFER_SINGLE])
	form.add_input_priority()
	form.add_note("接收转移可保持自身去向为空；费用可为扣款、收入或免费。")

func diagnose(_feature: InventoryHostFeatureDefinition, _layout: Resource, _features: Array[InventoryHostFeatureDefinition]) -> Array[Dictionary]:
	return [{"note": "钱包由运行时绑定注入。"}]
