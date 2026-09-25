@tool
extends RefCounted
## 描述配置入口；不创建编辑器预览节点。
func describe() -> Dictionary:
	return {"type": InventoryDescriptionFeatureDefinition, "title": "物品描述", "description": "归属：库存 Host 通用功能\n用途：显示库存物品的详情浮窗，支持悬停与主动查看。\n装配影响：为每个 Host 创建独立描述面板与延时计时器，并按配置注册查看输入动作。\n生效方式：悬停满足延时后展示；收到查看输入时展示；库存操作提交后刷新当前请求。", "category": "交互", "keywords": "详情 浮窗 面板"}

func build(form: Control) -> void:
	form.add_input_actions([InventoryInputActionIds.DESCRIBE])
	form.add_input_priority()
	form.add_field("panel_scene", "面板场景")
	form.add_field("hover_enabled", "启用悬停查看")
	form.add_field("hover_delay", "悬停延时（秒）")
	form.add_field("active_enabled", "启用主动查看")
	form.add_note("新建功能默认使用通用描述浮窗，可替换场景；主动清空后保持空值。场景根须实现 InventoryItemDescriptionPresenter。")

func diagnose(feature: InventoryHostFeatureDefinition, _layout: Resource, _features: Array[InventoryHostFeatureDefinition]) -> Array[Dictionary]:
	if feature.panel_source == InventoryDescriptionFeatureDefinition.PanelSource.SCENE and feature.panel_scene == null:
		return [{"error": "未配置描述面板场景。请选择面板场景。"}]
	if feature.panel_source == InventoryDescriptionFeatureDefinition.PanelSource.EXISTING and feature.existing_panel_path.is_empty():
		return [{"note": "绑定模式未设置路径：组装前必须按 InventoryDescriptionFeatureDefinition 类型注入现有面板。"}]
	return []
