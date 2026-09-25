@tool
extends RefCounted

func describe() -> Dictionary:
	return {"type": InventoryOperationRulesFeatureDefinition, "title": "物品标签", "description": "归属：ItemTagPart\n用途：让本面板遵守物品上的拿取、放入、消耗与无限供应标签。\n装配影响：为每个 Host 提供操作策略，供拿放与转移在规划时读取。\n生效方式：操作规划时汇入策略；开启无限供应时，普通拿取生成新实例并保留来源。", "category": "交互", "keywords": "禁止 拿取 放入 消耗 无限 供应 标签"}

func build(form: Control) -> void:
	form.add_note("只影响带对应标签的物品。整面板禁止拿取或放入时，请移除对应输入功能。")
	form.add_field("respect_no_take_tag", "遵守物品的禁止拿取标签")
	form.add_field("respect_no_place_tag", "遵守物品的禁止放入标签")
	form.add_field("respect_no_consume_tag", "遵守物品的禁止消耗标签")
	form.add_field("respect_infinite_supply_tag", "遵守物品的无限供应标签")
	form.add_note("无限供应：开启时，普通拿取生成新物品并保留来源；关闭时，按普通物品拿取与快捷转移。无限拿取功能对面板全部物品生效。")

func diagnose(_feature: InventoryHostFeatureDefinition, _layout: Resource, _features: Array[InventoryHostFeatureDefinition]) -> Array[Dictionary]:
	return []
