@abstract
class_name FreeInventoryPanelAssemblyDefinition
extends InventoryPanelAssemblyDefinition
## FREE 面板的抽象形式层：定义"每个可显示物品实例对应一个独立格子"的共享形式，
## 不承诺最终排布，禁止直接实例化、保存为标准预设或配置给 Host。
## 共享实现覆盖实例格面板创建/恢复、数据响应、命中与独立实例输入语义；
## 最终排布、额外布局节点与布局尺寸口径由具体子类（如 ORBIT）经模板接缝补齐。






func create_assembly(context: InventoryPanelAssemblyContext) -> InventoryPanelAssembly:
	if not _validate_configuration(context):
		return null
	var assembly := InventoryPanelAssembly.new()
	if not _create_layout_nodes(assembly, context):
		assembly.teardown()
		return null
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
	var assembly := InventoryPanelAssembly.new()
	if not _recover_layout_nodes(assembly, context):
		assembly.teardown()
		return null
	var controller := (
		context.host.get_node_or_null("InventoryItemsInputController")
		as InventoryItemsInputController
	)
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
	if assembly == null or assembly.get_part(FreeItemsPanel) == null:
		return false
	var controller := assembly.get_input_controller()
	if controller == null:
		return false
	if controller != null and not _is_controller_compatible(controller):
		return false
	return _is_layout_valid(assembly, context)


func refresh_assembly(
	assembly: InventoryPanelAssembly,
	context: InventoryPanelAssemblyContext
) -> void:
	var panel := assembly.get_part(FreeItemsPanel) as FreeItemsPanel
	var controller := assembly.get_input_controller()
	if panel == null:
		return
	panel.cell_size = context.cell_size
	_apply_layout_configuration(assembly, panel, context)
	panel.set_view_provider(context.view_provider)
	panel.inventory_data = context.inventory_data
	if controller != null:
		controller.inventory_data = context.inventory_data
		var free_controller := controller as FreeItemsInputController
		if free_controller == null:
			push_error("FREE 控制器必须继承 FreeItemsInputController")
			return
		free_controller.free_panel = panel
		panel.bind_items_input_controller(free_controller)


func get_preferred_size(
	assembly: InventoryPanelAssembly,
	_context: InventoryPanelAssemblyContext
) -> Vector2:
	var panel := assembly.get_part(FreeItemsPanel) as FreeItemsPanel
	return _get_layout_preferred_size(panel) if panel != null else Vector2.ZERO


#region 子类接缝

## 创建布局节点：默认创建实例格面板；具体子类追加自身布局节点（如轨道）并注册公开部件。
func _create_layout_nodes(
	assembly: InventoryPanelAssembly,
	context: InventoryPanelAssemblyContext
) -> bool:
	var panel := FreeItemsPanel.new()
	panel.name = "FreeItemsPanel"
	context.mount_owned_node(assembly, panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	assembly.register_part(FreeItemsPanel, panel)
	return true


## 恢复编辑器保存的布局节点：默认恢复实例格面板；具体子类同步恢复自身布局节点，
## 缺失、多余或类型不符时返回 false 交由上层拒绝重建。
func _recover_layout_nodes(
	assembly: InventoryPanelAssembly,
	context: InventoryPanelAssemblyContext
) -> bool:
	var panel := context.host.get_node_or_null("FreeItemsPanel") as FreeItemsPanel
	if panel == null:
		return false
	assembly.add_owned_node(panel)
	assembly.register_part(FreeItemsPanel, panel)
	return true


## 下发布局专属配置；在库存数据下发前调用，保证格子生成时挂载目标与布局参数已就位。
func _apply_layout_configuration(
	_assembly: InventoryPanelAssembly,
	_panel: FreeItemsPanel,
	_context: InventoryPanelAssemblyContext
) -> void:
	pass


## 校验布局专属部件与内部绑定是否完整。
func _is_layout_valid(
	_assembly: InventoryPanelAssembly,
	_context: InventoryPanelAssemblyContext
) -> bool:
	return true


## 首选尺寸口径：默认按实例格流式包围盒估算；具体子类按自身布局覆盖。
func _get_layout_preferred_size(panel: FreeItemsPanel) -> Vector2:
	return panel.get_free_preferred_size()

#endregion


func _validate_configuration(_context: InventoryPanelAssemblyContext) -> bool:
	return true


func _create_controller() -> FreeItemsInputController:
	return FreeItemsInputController.new()


func _is_controller_compatible(controller: InventoryItemsInputController) -> bool:
	return controller != null and controller.get_script() == FreeItemsInputController


func _connect_size_signals(assembly: InventoryPanelAssembly) -> void:
	var panel := assembly.get_part(FreeItemsPanel) as FreeItemsPanel
	if panel != null and not panel.minimum_size_changed.is_connected(
		assembly.notify_size_invalidated
	):
		panel.minimum_size_changed.connect(assembly.notify_size_invalidated)
