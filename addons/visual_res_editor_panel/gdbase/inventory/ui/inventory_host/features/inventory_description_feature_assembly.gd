extends InventoryHostFeatureAssembly
## 单 Host 描述请求生命周期；只清理自己的请求和自己实例化的面板。
var configuration: Resource
var presenter: InventoryItemDescriptionPresenter
var _host: InventoryHost
var _inventory: InventoryData
var _timer: Timer
var _hover_item: ItemInstanceData
var _tree: SceneTree
var _controller: InventoryItemsInputController
var _pointer_was_over_panel := false

func refresh(context: InventoryHostFeatureContext) -> bool:
	_host = context.host
	if _controller != context.input_controller:
		if is_instance_valid(_controller):
			_controller.set_pointer_observer(self, false)
		_controller = context.input_controller
	var next_presenter: InventoryItemDescriptionPresenter = presenter
	if configuration.panel_source == 1:
		var dependency := _host.get_feature_dependency(InventoryDescriptionFeatureDefinition)
		if dependency != null:
			next_presenter = dependency as InventoryItemDescriptionPresenter
		elif not configuration.existing_panel_path.is_empty():
			next_presenter = _host.get_node_or_null(configuration.existing_panel_path) as InventoryItemDescriptionPresenter
		else:
			next_presenter = null
		if not is_instance_valid(next_presenter) or next_presenter.is_queued_for_deletion():
			push_error("inventory_description_binding_missing: " + str(_host.get_path()))
			return false
	elif not is_instance_valid(presenter):
		var instance: Node = configuration.panel_scene.instantiate()
		next_presenter = instance as InventoryItemDescriptionPresenter
		if next_presenter == null:
			instance.free()
			push_error("inventory_description_panel_type_invalid")
			return false
		instance.name = "ItemDescription"
		_host.add_child(instance)
		add_owned_node(instance)
	if presenter != next_presenter or _inventory != context.inventory_data:
		_cancel_request()
	presenter = next_presenter
	if _inventory != context.inventory_data:
		_disconnect_inventory()
	_inventory = context.inventory_data
	if _inventory != null and not _inventory.operation_committed.is_connected(_on_operation_committed):
		_inventory.operation_committed.connect(_on_operation_committed)
	if _timer == null:
		_timer = Timer.new()
		_timer.one_shot = true
		_host.add_child(_timer)
		add_owned_node(_timer)
		_timer.timeout.connect(_show_hover)
		_host.mouse_pointed_item_instance.connect(_on_hover)
		_host.visibility_changed.connect(_on_context_changed)
		_host.input_context_changed.connect(_on_context_changed)
		_tree = _host.get_tree()
	_on_context_changed()
	return true

func _on_operation_committed(_result: InventoryOperationResult) -> void:
	if _can_show() and presenter.owns_request(self):
		presenter.refresh_inventory_item()

func _disconnect_inventory() -> void:
	if _inventory != null and _inventory.operation_committed.is_connected(_on_operation_committed):
		_inventory.operation_committed.disconnect(_on_operation_committed)

func describe(item: ItemInstanceData) -> bool:
	if not configuration.active_enabled or not _can_show() or item == null:
		return false
	_timer.stop()
	return presenter.request_inventory_item(self, item, true)

func _can_show() -> bool:
	return not _torn_down and is_instance_valid(_host) and _host.is_inside_tree() and _host.input_enabled and _host.is_visible_in_tree() and is_instance_valid(presenter) and presenter.is_inside_tree() and not presenter.is_queued_for_deletion()

func _on_hover(item: ItemInstanceData) -> void:
	if not configuration.hover_enabled or not _can_show():
		_cancel_request()
		return
	if _hover_item == item:
		return
	_timer.stop()
	_hover_item = item
	if presenter.is_request_pinned():
		return
	if item == null:
		_watch_pointer()
		return
	presenter.release_inventory_request(self)
	_timer.start(maxf(configuration.hover_delay, 0.001))
	_watch_pointer()

func _show_hover() -> void:
	if _can_show() and configuration.hover_enabled and _hover_item != null:
		presenter.request_inventory_item(self, _hover_item, false)

func _watch_pointer() -> void:
	if _tree != null and not _tree.process_frame.is_connected(_check_pointer):
		_tree.process_frame.connect(_check_pointer)

func _check_pointer() -> void:
	if not _can_show():
		_cancel_request()
		return
	var over_panel := presenter.is_pointer_over_panel()
	var left_panel := _pointer_was_over_panel and not over_panel
	_pointer_was_over_panel = over_panel
	if presenter.is_request_pinned() or over_panel:
		return
	if left_panel and is_instance_valid(_controller):
		# 浮窗遮挡网格时，网格退出事件可能仍解析到原格子；离开浮窗后重新取目标。
		_controller.refresh_mouse_pointed_item()
		_on_hover(_controller.get_mouse_pointed_item_instance())
	if _hover_item == null:
		presenter.release_inventory_request(self)
		_stop_watching()

func _stop_watching() -> void:
	_pointer_was_over_panel = false
	if _tree != null and _tree.process_frame.is_connected(_check_pointer):
		_tree.process_frame.disconnect(_check_pointer)

func _on_context_changed() -> void:
	if is_instance_valid(_controller):
		_controller.set_pointer_observer(self, configuration.hover_enabled and is_instance_valid(presenter) and _host.input_enabled and _host.is_visible_in_tree())
	if not _can_show():
		_cancel_request()

func _cancel_request() -> void:
	if is_instance_valid(_timer):
		_timer.stop()
	_hover_item = null
	_stop_watching()
	if is_instance_valid(presenter):
		presenter.release_inventory_request(self)

func teardown() -> void:
	_cancel_request()
	_disconnect_inventory()
	if is_instance_valid(_controller):
		_controller.set_pointer_observer(self, false)
	_controller = null
	if is_instance_valid(_host):
		if _host.mouse_pointed_item_instance.is_connected(_on_hover):
			_host.mouse_pointed_item_instance.disconnect(_on_hover)
		if _host.visibility_changed.is_connected(_on_context_changed):
			_host.visibility_changed.disconnect(_on_context_changed)
		if _host.input_context_changed.is_connected(_on_context_changed):
			_host.input_context_changed.disconnect(_on_context_changed)
	presenter = null
	_host = null
	_inventory = null
	super.teardown()
