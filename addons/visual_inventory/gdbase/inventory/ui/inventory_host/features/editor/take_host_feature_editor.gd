@tool
extends RefCounted
## 此功能的编辑适配，运行时不引用本文件。
func describe() -> Dictionary:
	return {"type": InventoryTakeFeatureDefinition, "title": "基础拿取", "description": "归属：库存 Host 通用功能\n用途：从当前库存拿起整组或单件物品。\n装配影响：为每个 Host 创建独立的拿取处理器，并注册对应输入动作。\n生效方式：收到拿取输入时执行，将取得的物品交给手持会话。", "role_titles": {InventoryHostFeatureRoles.TAKE: "拿取"}, "category": "交互", "keywords": ""}

func build(form: Control) -> void:
	form.add_input_actions([InventoryInputActionIds.PRIMARY, InventoryInputActionIds.PRIMARY_SINGLE])
	form.add_input_priority()

func diagnose(_feature: InventoryHostFeatureDefinition, _layout: Resource, _features: Array[InventoryHostFeatureDefinition]) -> Array[Dictionary]:
	return []
