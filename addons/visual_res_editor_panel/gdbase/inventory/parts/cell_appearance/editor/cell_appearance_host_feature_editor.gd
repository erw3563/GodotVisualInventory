@tool
extends RefCounted
## 物品框功能的编辑适配，装配外观键页面与全局设置。
const AppearanceEditor = preload("res://addons/visual_res_editor_panel/gdbase/inventory/parts/cell_appearance/editor/inventory_cell_appearance_editor.gd")
func describe() -> Dictionary:
	return {"type": InventoryCellAppearanceFeatureDefinition, "title": "物品框", "description": "归属：ItemCellAppearancePart\n用途：显示已放置物品的边框、放置预览和无效操作反馈。\n装配影响：在当前 Host 下创建独立覆盖层节点。\n生效方式：监听手持状态和操作反馈，在面板可交互且持有物品期间逐帧更新放置预览。\n外部依赖：需要 GRID 布局提供底板。", "category": "物品能力", "keywords": "边框 预览 反馈 placed placeable"}

func build(form: Control) -> void:
	form.declared_fields.append("default_cell_appearance_part")
	var editor := AppearanceEditor.new()
	editor.setup(form, true)
	form.add_child(editor)
	form.controls["default_cell_appearance_part"] = editor
	var toggle := Button.new()
	toggle.name = "CommonSettings"
	toggle.text = "此背包公共设置"
	toggle.toggle_mode = true
	toggle.button_pressed = editor.state.get("common_expanded", false)
	form.add_child(toggle)
	var first: int = form.get_child_count()
	form.add_field("show_placed_border", "显示常驻边框")
	form.add_field("show_place_preview", "显示放置预览")
	form.add_field("border_width", "默认线宽（像素）")
	form.add_field("invalid_click_feedback_time", "失败反馈时长（秒）")
	var fields: Array[Node] = []
	for index in range(first, form.get_child_count()):
		fields.append(form.get_child(index))
		form.get_child(index).visible = toggle.button_pressed
	toggle.toggled.connect(func(expanded: bool):
		editor.state["common_expanded"] = expanded
		for field in fields:
			field.visible = expanded
	)

func diagnose(feature: InventoryHostFeatureDefinition, layout: Resource, features: Array[InventoryHostFeatureDefinition]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if layout is GridInventoryPanelAssemblyDefinition:
		if not layout.create_grid_panel:
			result.append({"error": "物品框需要 GRID 底板，请在布局栏目开启底板。"})
	elif layout is CatalogInventoryPanelAssemblyDefinition or layout is OrbitInventoryPanelAssemblyDefinition:
		result.append({"error": "当前布局不提供 GRID 部件，不能装配物品框。"})
	else:
		result.append({"note": "自定义布局的 GRID 能力待运行时验证。"})
	if feature.default_cell_appearance_part != null:
		var reason: StringName = feature.default_cell_appearance_part.validate_appearances()
		if not reason.is_empty():
			result.append({"error": "默认外观条目无效：" + str(reason)})
	else:
		result.append({"note": "未配置默认外观；需要显式配置样式键。"})
	for key in ["border_width", "invalid_click_feedback_time"]:
		if not is_finite(feature.get(key)) or feature.get(key) < 0.0:
			result.append({"error": key + " 必须是非负有限数值。"})
	return result
