@tool
extends RefCounted
## 此功能的编辑适配，运行时不引用本文件。
func describe() -> Dictionary:
	return {"type": ItemAnimationFeatureDefinition, "title": "物品动画", "description": "归属：ItemAnimationPart\n用途：为库存物品提供动画播放能力。\n装配影响：申请场景共享动画播放器，多个 Host 共用同一服务。\n生效方式：收到播放请求时执行动画；卸载时释放租约，最后一个使用者释放后销毁播放器。\n外部依赖：动画外观在物品 Part 中配置；需要场景库存服务。", "category": "物品能力", "keywords": "动画 播放"}

func build(form: Control) -> void:
	form.add_note("具体外观与动画片段在物品 Part 中配置。")

func diagnose(feature: InventoryHostFeatureDefinition, layout: Resource, features: Array[InventoryHostFeatureDefinition]) -> Array[Dictionary]:
	return [{"note": "具体外观与动画片段在物品 Part 中配置。"}]
