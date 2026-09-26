@tool
extends RefCounted
## 此功能的编辑适配，运行时不引用本文件。
func describe() -> Dictionary:
	return {"type": NestedInventoryCyclePreventionFeatureDefinition, "title": "嵌套库存防环", "description": "归属：ItemInventoryPart\n用途：阻止物品进入会形成子库存所有权环的目标库存。\n装配影响：为每个 Host 向操作端点贡献防环 Rule。\n生效方式：规划与提交复核时读取本端点策略；未安装时允许成环。\n外部依赖：嵌套开窗功能不隐式安装本功能；子窗口需在继承列表中显式勾选。", "category": "物品能力", "keywords": "防环 嵌套 循环 子背包"}

func build(form: Control) -> void:
	form.add_note("仅约束本 Host 作为目标端点时的进入与嵌套 State 更新；源端点策略不替目标限制。SYSTEM 与未安装端点允许成环。")

func diagnose(_feature: InventoryHostFeatureDefinition, _layout: Resource, _features: Array[InventoryHostFeatureDefinition]) -> Array[Dictionary]:
	return []
