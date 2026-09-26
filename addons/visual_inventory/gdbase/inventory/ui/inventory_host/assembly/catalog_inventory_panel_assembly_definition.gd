@tool
class_name CatalogInventoryPanelAssemblyDefinition
extends InventoryPanelAssemblyDefinition
## CATALOG 面板的具体装配定义。
## 背景 InventoryPanelBackground——StyleBox 与可选材质，最先挂载且忽略指针；
## 目录面板 ItemCatalogPanel——按物品等价规则聚合行；
## 输入控制器 CatalogItemsInputController——接管目录指针交互。

## 是否创建纯显示背景（最先挂载，尺寸跟随目录首选尺寸）。
@export var create_background := false
## 背景 StyleBox；空值不绘制面板样式。
@export var background_style: StyleBox
## 背景材质（含 ShaderMaterial）；赋给背景节点。
@export var background_material: Material
@export_enum("名称升序", "名称降序", "数量降序") var sort_rule := 0
@export var show_icon := true
@export var row_style: StyleBox
@export var row_hover_style: StyleBox
@export var row_material: Material
@export var icon_modulate := Color.WHITE
@export var name_font_color := Color.WHITE
@export_range(0, 128, 1, "or_greater") var name_font_size := 0
@export var count_font_color := Color(0.92, 0.86, 0.6, 1.0)
@export_range(0, 128, 1, "or_greater") var count_font_size := 0
@export_range(16, 256, 1, "or_greater") var row_height := 32
@export var min_panel_size := Vector2(216.0, 96.0)
@export var max_panel_height := 360.0
@export var show_capacity_header := true


func create_assembly(context: InventoryPanelAssemblyContext) -> InventoryPanelAssembly:
	if not _validate_configuration():
		return null
	var assembly := InventoryPanelAssembly.new()
	if create_background:
		var background := InventoryPanelBackground.new()
		background.name = "InventoryPanelBackground"
		context.mount_owned_node(assembly, background)
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		assembly.register_part(InventoryPanelBackground, background)
	var panel := _create_panel()
	panel.apply_configuration(_panel_configuration(context))
	panel.name = "ItemCatalogPanel"
	context.mount_owned_node(assembly, panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	assembly.register_part(ItemCatalogPanel, panel)
	var controller := _create_controller()
	if controller == null:
		assembly.teardown()
		return null
	controller.name = "InventoryItemsInputController"
	context.mount_owned_node(assembly, controller)
	assembly.set_input_controller(controller)
	assembly.register_part(InventoryItemsInputController, controller)
	_connect_size_signals(assembly)
	refresh_assembly(assembly, context)
	return assembly


func recover_assembly(context: InventoryPanelAssemblyContext) -> InventoryPanelAssembly:
	var background := (
		context.host.get_node_or_null("InventoryPanelBackground") as InventoryPanelBackground
	)
	var panel := context.host.get_node_or_null("ItemCatalogPanel") as ItemCatalogPanel
	# 同名节点不代表归本布局所有；不能收编或删除其它布局的面板。
	if panel != null and panel.get_script() != ItemCatalogPanel:
		return null
	var controller := (
		context.host.get_node_or_null("InventoryItemsInputController")
		as InventoryItemsInputController
	)
	var assembly := InventoryPanelAssembly.new()
	if background != null:
		assembly.add_owned_node(background)
		assembly.register_part(InventoryPanelBackground, background)
	if panel != null:
		assembly.add_owned_node(panel)
		assembly.register_part(ItemCatalogPanel, panel)
	if controller != null:
		assembly.add_owned_node(controller)
		assembly.set_input_controller(controller)
		assembly.register_part(InventoryItemsInputController, controller)
	if not validate_assembly(assembly, context):
		assembly.teardown()
		return null
	_connect_size_signals(assembly)
	return assembly


func validate_assembly(
	assembly: InventoryPanelAssembly,
	context: InventoryPanelAssemblyContext
) -> bool:
	if assembly == null or assembly.get_part(ItemCatalogPanel) == null or not configuration_problem().is_empty():
		return false
	if create_background != (assembly.get_part(InventoryPanelBackground) != null):
		return false
	var panel := assembly.get_part(ItemCatalogPanel) as ItemCatalogPanel
	if panel.get_script() != ItemCatalogPanel or panel.get_parent() != context.host:
		return false
	var controller := assembly.get_input_controller()
	if controller == null:
		return false
	return controller.get_script() == CatalogItemsInputController and controller.get_parent() == context.host and assembly.has_valid_owned_nodes()


func refresh_assembly(
	assembly: InventoryPanelAssembly,
	context: InventoryPanelAssemblyContext
) -> void:
	var background := assembly.get_part(InventoryPanelBackground) as InventoryPanelBackground
	var panel := assembly.get_part(ItemCatalogPanel) as ItemCatalogPanel
	var controller := assembly.get_input_controller()
	if panel == null:
		return
	if background != null:
		background.configure(background_style, background_material)
	panel.apply_configuration(_panel_configuration(context))
	panel.set_view_provider(context.view_provider)
	panel.inventory_data = context.inventory_data
	if controller != null:
		controller.inventory_data = context.inventory_data
		var catalog_controller := controller as CatalogItemsInputController
		if catalog_controller == null:
			push_error("CATALOG 控制器必须继承 CatalogItemsInputController")
			return
		catalog_controller.catalog_panel = panel
		panel.bind_items_input_controller(catalog_controller)
	_apply_background_size(assembly, context)


func get_preferred_size(
	assembly: InventoryPanelAssembly,
	_context: InventoryPanelAssemblyContext
) -> Vector2:
	var panel := assembly.get_part(ItemCatalogPanel) as ItemCatalogPanel
	return panel.get_catalog_preferred_size() if panel != null else Vector2.ZERO


func _create_controller() -> CatalogItemsInputController:
	return CatalogItemsInputController.new()


func _create_panel() -> ItemCatalogPanel:
	return ItemCatalogPanel.new()


func configuration_problem() -> String:
	if sort_rule < 0 or sort_rule > 2:
		return "排序方式无效"
	if row_height < 16:
		return "每排高度至少为 16"
	if not min_panel_size.is_finite() or min_panel_size.x <= 0 or min_panel_size.y <= 0:
		return "目录面板最小尺寸必须为正有限值"
	if not is_finite(max_panel_height) or max_panel_height < min_panel_size.y:
		return "最大高度必须为有限值且不小于最小高度"
	return ""


func _validate_configuration() -> bool:
	var problem := configuration_problem()
	if not problem.is_empty():
		push_warning(problem)
	return problem.is_empty()


func _panel_configuration(context: InventoryPanelAssemblyContext) -> Dictionary:
	return {
		"sort_rule": sort_rule,
		"show_icon": show_icon,
		"row_style": row_style,
		"row_hover_style": row_hover_style,
		"row_material": row_material,
		"icon_modulate": icon_modulate,
		"name_font_color": name_font_color,
		"name_font_size": name_font_size,
		"count_font_color": count_font_color,
		"count_font_size": count_font_size,
		"row_height": row_height,
		"min_panel_size": min_panel_size,
		"max_panel_height": max_panel_height,
		"show_capacity_header": show_capacity_header,
		"cell_size": context.cell_size,
	}


func _connect_size_signals(assembly: InventoryPanelAssembly) -> void:
	var panel := assembly.get_part(ItemCatalogPanel) as ItemCatalogPanel
	if panel != null and not panel.minimum_size_changed.is_connected(
		assembly.notify_size_invalidated
	):
		panel.minimum_size_changed.connect(assembly.notify_size_invalidated)


## 首选尺寸同步为背景最小尺寸与当前尺寸，保持与目录面板对齐。
func _apply_background_size(
	assembly: InventoryPanelAssembly,
	context: InventoryPanelAssemblyContext
) -> void:
	var background := assembly.get_part(InventoryPanelBackground) as InventoryPanelBackground
	if background == null:
		return
	var size := get_preferred_size(assembly, context)
	if size.x <= 0.0 or size.y <= 0.0:
		return
	background.custom_minimum_size = size
	background.size = size
