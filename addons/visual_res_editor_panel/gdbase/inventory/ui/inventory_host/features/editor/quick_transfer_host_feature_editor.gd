@tool
extends RefCounted
## 此功能的编辑适配，运行时不引用本文件。
func describe() -> Dictionary:
	return {"type": InventoryQuickTransferFeatureDefinition, "title": "基础转移", "description": "归属：库存 Host 通用功能\n用途：将单件或整组物品直接转移到目标背包。\n装配影响：为每个 Host 创建免费转移贡献与快捷转移处理器，并注册对应输入动作。\n生效方式：收到快捷转移输入时，经转移中心搬移物品。\n外部依赖：主动转出由场景组装方配置转移目标 Host；对端需要转移功能。", "role_titles": {InventoryHostFeatureRoles.TRANSFER: "转移"}, "category": "交互", "keywords": "快捷转移 目标背包"}

func build(form: Control) -> void:
	form.add_input_actions([InventoryInputActionIds.QUICK_TRANSFER, InventoryInputActionIds.QUICK_TRANSFER_SINGLE])
	form.add_input_priority()
	form.add_note("主动转出需配置 transfer_target_host；接收转移可保持去向为空。")

func diagnose(feature: InventoryHostFeatureDefinition, layout: Resource, features: Array[InventoryHostFeatureDefinition]) -> Array[Dictionary]:
	return [{"note": "主动转出需配置 transfer_target_host；接收转移可保持去向为空。"}]
