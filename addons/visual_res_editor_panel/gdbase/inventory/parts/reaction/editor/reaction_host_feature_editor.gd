@tool
extends RefCounted
## 此功能的编辑适配，运行时不引用本文件。
func describe() -> Dictionary:
	return {"type": InventoryReactionFeatureDefinition, "title": "反应效果", "description": "归属：ItemReactionPart\n用途：执行物品配置的反应规则，并可能变更库存内容。\n装配影响：申请场景共享反应服务，按库存去重申请连锁执行器。\n生效方式：物品加入、位置变化或操作提交时评估；外部可触发回合结束；卸载时释放租约。\n外部依赖：反应规则在物品 Part 中配置；需要场景库存服务。", "category": "物品能力", "keywords": "反应 连锁 计数器"}

func build(form: Control) -> void:
	form.add_field("reaction_delay_seconds", "反应延迟（秒）")
	form.add_note("反应规则在物品 Part 中配置。")

func diagnose(feature: InventoryHostFeatureDefinition, layout: Resource, features: Array[InventoryHostFeatureDefinition]) -> Array[Dictionary]:
	if not is_finite(feature.reaction_delay_seconds) or feature.reaction_delay_seconds < 0:
		return [{"error": "反应延迟必须是非负有限数值。"}]
	return []
