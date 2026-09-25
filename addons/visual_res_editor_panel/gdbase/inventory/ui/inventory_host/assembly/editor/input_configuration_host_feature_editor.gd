@tool
extends RefCounted
## 此功能的编辑适配，运行时不引用本文件。
func describe() -> Dictionary:
	return {"type": InventoryInputConfigurationFeatureDefinition, "title": "高级输入", "description": "归属：库存 Host 装配\n用途：为本 Host 追加专业输入路由与观察者。\n装配影响：为每个 Host 注册配置中的动作路由与观察者。\n生效方式：运行时按所配路由与观察者处理输入。\n外部依赖：路由与观察者为专业资源配置，由作者在参数区指定。", "category": "高级／项目功能", "keywords": "路由 观察者 输入"}

func build(form: Control) -> void:
	var action_ids: Array[StringName] = []
	for route in form.resource.action_routes:
		if route != null and route.action_id not in action_ids:
			action_ids.append(route.action_id)
	form.add_input_actions(action_ids)
	form.add_input_priority()
	form.add_field("action_routes", "动作路由")
	form.add_field("action_observers", "动作观察者")
	form.add_note("路由与观察者为专业资源；编辑器展示配置，运行时由 Host 装配执行。")

func diagnose(feature: InventoryHostFeatureDefinition, layout: Resource, features: Array[InventoryHostFeatureDefinition]) -> Array[Dictionary]:
	for array in [feature.action_routes, feature.action_observers]:
		if array.has(null):
			return [{"error": "动作路由或观察者含空项，请补全或删除。"}]
	for route in feature.action_routes:
		if route.processors.has(null):
			return [{"error": "动作处理器列表含空项。"}]
	return []
