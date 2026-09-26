@tool
extends RefCounted
## 此功能的编辑适配，运行时不引用本文件。
func describe() -> Dictionary:
	return {"type": NestedInventoryHostFeatureDefinition, "title": "嵌套库存", "description": "归属：ItemInventoryPart\n用途：打开物品携带的子背包窗口。\n装配影响：申请场景共享嵌套窗口服务，并为每个 Host 创建打开处理器与 Part 处理器。\n生效方式：收到打开输入时创建或显示子窗口；卸载时释放服务租约，最后一个使用者释放后销毁服务。\n外部依赖：需要场景库存服务；子功能仅继承父 Host 已勾选且已存在的类型，勾选嵌套自身允许递归打开。", "category": "物品能力", "keywords": "子背包 嵌套 打开"}

func build(form: Control) -> void:
	form.add_input_actions([InventoryInputActionIds.OPEN])
	form.add_input_priority()
	form.add_feature_types("inherited_feature_types", "子库存继承功能")
	form.add_note("仅继承父 Host 已有功能；缺席的勾选类型保留原值。勾选嵌套自身允许递归打开。")

func diagnose(feature: InventoryHostFeatureDefinition, layout: Resource, features: Array[InventoryHostFeatureDefinition]) -> Array[Dictionary]:
	if not feature.validate_configuration(features).is_empty():
		return []
	var inherited: Array[InventoryHostFeatureDefinition] = []
	for parent in features:
		if parent != null and parent.get_script() in feature.inherited_feature_types:
			inherited.append(parent)
	var result: Array[Dictionary] = []
	for issue in InventoryHostFeatureValidator.diagnose(inherited):
		result.append({"error": "继承组合无效：" + str(issue.reason)})
	return result
