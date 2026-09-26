@tool
extends RefCounted
## 此功能的编辑适配，运行时不引用本文件。
func describe() -> Dictionary:
	return {"type": InventoryRotateFeatureDefinition, "title": "基础旋转", "description": "归属：库存 Host 通用功能\n用途：旋转手持物品或目标格物品的朝向。\n装配影响：为每个 Host 创建独立的旋转处理器，并注册旋转输入动作。\n生效方式：收到旋转输入时执行。", "role_titles": {InventoryHostFeatureRoles.ROTATE: "旋转"}, "category": "交互", "keywords": ""}

func build(form: Control) -> void:
	form.add_input_actions([InventoryInputActionIds.ROTATE])
	form.add_input_priority()


func diagnose(feature: InventoryHostFeatureDefinition, layout: Resource, features: Array[InventoryHostFeatureDefinition]) -> Array[Dictionary]:
	return []
