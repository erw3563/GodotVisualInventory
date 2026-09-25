@tool
class_name InventoryCellAppearanceFeatureAssembly
extends InventoryHostFeatureAssembly
## 唯一拥有 ShapeOverlay 的功能；预览与反馈仅作用于当前 Host。
var configuration: InventoryCellAppearanceFeatureDefinition
var overlay: InventoryShapeOverlay
var _host: InventoryHost
var _session: InventoryHeldItemSession
var _controller: InventoryItemsInputController
var _tree: SceneTree

func refresh(context: InventoryHostFeatureContext) -> bool:
	var grid := context.panel_assembly.get_part(InventoryGridPanel) as InventoryGridPanel
	if grid == null:
		return false
	_host = context.host
	if not is_instance_valid(overlay):
		overlay = InventoryShapeOverlay.new()
		overlay.name = "InventoryShapeOverlay"
		# 功能节点不序列化；编辑器重开时重新创建，不由布局收编。
		_host.add_child(overlay)
		add_owned_node(overlay)
	overlay.inventory_grid_panel = grid
	overlay.default_cell_appearance_part = configuration.default_cell_appearance_part
	overlay.show_placed_border = configuration.show_placed_border
	overlay.show_place_preview = configuration.show_place_preview
	overlay.border_width = configuration.border_width
	overlay.invalid_click_feedback_time = configuration.invalid_click_feedback_time
	overlay.inventory_data = context.inventory_data
	overlay.refresh_placed_item_borders()
	if not context.is_editor_preview:
		bind_interaction(_host, context.input_controller)
	return true

## 编辑器交互工具可显式启用临时功能的输入观察。
func bind_interaction(host: InventoryHost, controller: InventoryItemsInputController) -> void:
	_host = host
	var session := _host.get_held_item_session()
	if _session != session:
		if is_instance_valid(_session) and _session.held_item_changed.is_connected(_update_preview):
			_session.held_item_changed.disconnect(_update_preview)
		_session = session
		if _session != null:
			_session.held_item_changed.connect(_update_preview)
	if _controller != controller:
		if is_instance_valid(_controller) and _controller.operation_feedback_requested.is_connected(_on_feedback):
			_controller.operation_feedback_requested.disconnect(_on_feedback)
		_controller = controller
		if _controller != null:
			_controller.operation_feedback_requested.connect(_on_feedback)
	_tree = _host.get_tree()
	if not _host.visibility_changed.is_connected(_update_preview):
		_host.visibility_changed.connect(_update_preview)
	if not _host.input_context_changed.is_connected(_update_preview):
		_host.input_context_changed.connect(_update_preview)
	_update_preview()

func _update_preview() -> void:
	if not is_instance_valid(overlay) or not is_instance_valid(_host):
		return
	var session := _host.get_held_item_session()
	if _session != session:
		if is_instance_valid(_session) and _session.held_item_changed.is_connected(_update_preview):
			_session.held_item_changed.disconnect(_update_preview)
		_session = session
		if _session != null:
			_session.held_item_changed.connect(_update_preview)
	var holding := is_instance_valid(_session) and _session.has_held_item()
	var observing := holding and _host.input_enabled and _host.is_visible_in_tree()
	if _tree != null:
		if observing and not _tree.process_frame.is_connected(_update_preview):
			_tree.process_frame.connect(_update_preview)
		elif not observing and _tree.process_frame.is_connected(_update_preview):
			_tree.process_frame.disconnect(_update_preview)
	if not holding or not _host.input_enabled or not _host.is_visible_in_tree() or overlay.inventory_data == null:
		overlay.clear_preview()
		return
	var cell := overlay.inventory_grid_panel.get_mouse_cell()
	if cell == Vector2i(-1, -1):
		overlay.clear_preview()
		return
	var item := _session.get_held_item()
	var inventory := overlay.inventory_data
	var valid := inventory.can_place_item_in_cell(InventoryOperationContext.for_endpoint(_host.get_operation_endpoint()), item, cell) or inventory.can_merge_item_in_cell(InventoryOperationContext.for_endpoint(_host.get_operation_endpoint()), item, cell) or inventory.can_replace_item_in_cell(InventoryOperationContext.for_endpoint(_host.get_operation_endpoint()), item, cell)
	overlay.set_preview_cells(inventory.get_preview_cells_for_item(item, cell), valid, item)

func _on_feedback(item: ItemInstanceData) -> void:
	if is_instance_valid(overlay):
		overlay.play_invalid_action_feedback(item)

func teardown() -> void:
	if _tree != null and _tree.process_frame.is_connected(_update_preview):
		_tree.process_frame.disconnect(_update_preview)
	if is_instance_valid(_session) and _session.held_item_changed.is_connected(_update_preview):
		_session.held_item_changed.disconnect(_update_preview)
	if is_instance_valid(_controller) and _controller.operation_feedback_requested.is_connected(_on_feedback):
		_controller.operation_feedback_requested.disconnect(_on_feedback)
	if is_instance_valid(_host) and _host.visibility_changed.is_connected(_update_preview):
		_host.visibility_changed.disconnect(_update_preview)
	if is_instance_valid(_host) and _host.input_context_changed.is_connected(_update_preview):
		_host.input_context_changed.disconnect(_update_preview)
	super.teardown()
	overlay = null
	_host = null
	_session = null
	_controller = null
	_tree = null
