@tool
extends RefCounted
## 此功能的编辑适配，运行时不引用本文件。
func describe() -> Dictionary:
	return {"type": InventoryPlaceFeatureDefinition, "title": "基础放置", "description": "归属：库存 Host 通用功能\n用途：将手持的整组或单件物品放入当前库存，并按布局规则合并或交换。\n装配影响：为每个 Host 创建独立的放置处理器，并注册对应输入动作。\n生效方式：收到放置输入时执行，写入目标库存并更新手持状态。", "role_titles": {InventoryHostFeatureRoles.PLACE: "放置"}, "category": "交互", "keywords": ""}

func build(form: Control) -> void:
	form.add_input_actions([InventoryInputActionIds.PRIMARY, InventoryInputActionIds.PRIMARY_SINGLE])
	form.add_input_priority()

func diagnose(_feature: InventoryHostFeatureDefinition, _layout: Resource, _features: Array[InventoryHostFeatureDefinition]) -> Array[Dictionary]:
	return []
