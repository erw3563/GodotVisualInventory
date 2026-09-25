@tool
class_name GridInventoryPanelAssemblyDefinition
extends InventoryPanelAssemblyDefinition
## GRID 面板的具体装配定义。
## 背景 InventoryPanelBackground——StyleBox 与可选材质，最先挂载且忽略指针；
## 底板 InventoryGridPanel——由 OccupyMap 生成空间格，承担格子坐标与像素换算，
## 并作为指针输入面把事件转发给输入控制器；
## 物品层 GridInventoryItemsPanel——按格子坐标摆放物品图标（尺寸与格子一致）；
## 输入控制器 InventoryItemsInputController——统一接管背包指针交互。
## 场景作者无需预建 sibling 节点或填写 NodePath；恢复按同一套节点名定位。

## 是否创建纯显示背景（最先挂载，尺寸跟随首选尺寸）。
@export var create_background := false
## 背景 StyleBox；空值不绘制面板样式。
@export var background_style: StyleBox
## 背景材质（含 ShaderMaterial）；赋给背景节点。
@export var background_material: Material
@export var create_grid_panel := true
## 是否创建物品层（依赖底板做物品定位与图标尺寸）。
@export var create_items_panel := true
## 合法区域底板样式；空值表示透明底板。标准预设显式引用默认 StyleBoxTexture。
@export var cell_style: StyleBox
## 格子水平、垂直间距；分量须非负，成为 GRID 间距权威来源。
@export var cell_spacing: Vector2i = Vector2i(4, 4)
## 是否绘制合法格与空洞格底板；关闭后仍保留布局、坐标、物品显示与输入。
@export var show_cell_background := true
## 空洞格子装饰样式；空值表示透明占位，空洞保持无效目标语义。
@export var empty_cell_style: StyleBox

func create_assembly(context: InventoryPanelAssemblyContext) -> InventoryPanelAssembly:
	if not _validate_configuration(context):
		return null
	var assembly := InventoryPanelAssembly.new()
	var background: InventoryPanelBackground
	var grid: InventoryGridPanel
	var items: GridInventoryItemsPanel
	if create_background:
		background = InventoryPanelBackground.new()
		background.name = "InventoryPanelBackground"
		context.mount_owned_node(assembly, background)
		assembly.register_part(InventoryPanelBackground, background)
	if create_grid_panel:
		grid = InventoryGridPanel.new()
		grid.name = "InventoryGridPanel"
		context.mount_owned_node(assembly, grid)
		assembly.register_part(InventoryGridPanel, grid)
	if create_items_panel:
		items = GridInventoryItemsPanel.new()
		items.name = "GridInventoryItemsPanel"
		context.mount_owned_node(assembly, items)
		assembly.register_part(GridInventoryItemsPanel, items)
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
	if not _validate_configuration(context):
		return null
	var assembly := InventoryPanelAssembly.new()
	# 按 Host 范围内稳定节点名定位；缺失部件视作对应开关关闭，validate 兜底校验。
	var background := (
		context.host.get_node_or_null("InventoryPanelBackground") as InventoryPanelBackground
	)
	var grid := context.host.get_node_or_null("InventoryGridPanel") as InventoryGridPanel
	var items := context.host.get_node_or_null("GridInventoryItemsPanel") as GridInventoryItemsPanel
	var controller := (
		context.host.get_node_or_null("InventoryItemsInputController")
		as InventoryItemsInputController
	)
	_register_recovered(assembly, InventoryPanelBackground, background)
	_register_recovered(assembly, InventoryGridPanel, grid)
	_register_recovered(assembly, GridInventoryItemsPanel, items)
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
	if assembly == null:
		return false
	if create_background != (assembly.get_part(InventoryPanelBackground) != null):
		return false
	if create_grid_panel != (assembly.get_part(InventoryGridPanel) != null):
		return false
	if create_items_panel != (assembly.get_part(GridInventoryItemsPanel) != null):
		return false
	var controller := assembly.get_input_controller()
	if controller == null:
		return false
	return _is_controller_compatible(controller)


func refresh_assembly(
	assembly: InventoryPanelAssembly,
	context: InventoryPanelAssemblyContext
) -> void:
	var background := assembly.get_part(InventoryPanelBackground) as InventoryPanelBackground
	var grid := assembly.get_part(InventoryGridPanel) as InventoryGridPanel
	var items := assembly.get_part(GridInventoryItemsPanel) as GridInventoryItemsPanel
	var controller := assembly.get_input_controller()
	if background != null:
		background.configure(background_style, background_material)
	if grid != null:
		# 先应用完整样式与间距，再同步库存与布局尺寸。
		grid.configure_presentation(
			cell_style,
			empty_cell_style,
			show_cell_background,
			cell_spacing
		)
		grid.cell_size = context.cell_size
		grid.inventory_data = context.inventory_data
	if items != null:
		items.set_view_provider(context.view_provider)
		items.inventory_grid_panel = grid
		items.inventory_data = context.inventory_data
	if controller != null:
		controller.inventory_data = context.inventory_data
		controller.inventory_grid_panel = grid
	if grid != null and controller != null:
		grid.bind_items_input_controller(controller)
	_apply_grid_size(assembly, context)


func get_preferred_size(
	assembly: InventoryPanelAssembly,
	_context: InventoryPanelAssemblyContext
) -> Vector2:
	var grid := assembly.get_part(InventoryGridPanel) as InventoryGridPanel
	return grid.get_grid_size() if grid != null else Vector2.ZERO


func _validate_configuration(_context: InventoryPanelAssemblyContext) -> bool:
	# 物品层依赖底板换算格子坐标；关闭底板时也须关闭物品层。
	if create_items_panel and not create_grid_panel:
		push_error("GRID: ItemsPanel 需要 GridPanel")
		return false
	if cell_spacing.x < 0 or cell_spacing.y < 0:
		push_error("GRID: cell_spacing 分量须非负")
		return false
	return true


func _create_controller() -> InventoryItemsInputController:
	return InventoryItemsInputController.new()


func _is_controller_compatible(controller: InventoryItemsInputController) -> bool:
	# 精确匹配脚本，拒绝子类替换，保证 GRID 输入语义不被覆盖。
	return controller != null and controller.get_script() == InventoryItemsInputController


func _register_recovered(
	assembly: InventoryPanelAssembly,
	type: Script,
	node: Node
) -> void:
	if node == null:
		return
	assembly.add_owned_node(node)
	assembly.register_part(type, node)


func _connect_size_signals(assembly: InventoryPanelAssembly) -> void:
	var grid := assembly.get_part(InventoryGridPanel) as InventoryGridPanel
	if grid == null:
		return
	if not grid.updated.is_connected(assembly.notify_size_invalidated):
		grid.updated.connect(assembly.notify_size_invalidated)
	if not grid.cell_size_changed.is_connected(assembly.notify_size_invalidated):
		grid.cell_size_changed.connect(assembly.notify_size_invalidated)


func _apply_grid_size(
	assembly: InventoryPanelAssembly,
	context: InventoryPanelAssemblyContext
) -> void:
	var size := get_preferred_size(assembly, context)
	if size.x <= 0.0 or size.y <= 0.0:
		return
	# 首选尺寸同步为背景与物品层最小尺寸，保持对齐。
	var background := assembly.get_part(InventoryPanelBackground) as InventoryPanelBackground
	if background != null:
		background.custom_minimum_size = size
		background.size = size
	var items := assembly.get_part(GridInventoryItemsPanel) as GridInventoryItemsPanel
	if items != null:
		items.custom_minimum_size = size
		items.size = size
