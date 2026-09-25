class_name NestedInventoryWindow
extends PanelContainer
## 背包型物品的可拖动独立浮窗，内含完整 InventoryHost。

signal close_requested(window: NestedInventoryWindow)
signal bring_to_front_requested(window: NestedInventoryWindow)

const TITLE_HEIGHT := 28.0
const CLOSE_BUTTON_WIDTH := 28.0
const CONTENT_MARGIN := 8.0

## 打开本窗口的背包物品实例。
var source_item_instance: ItemInstanceData
## Processor 已解析的子库存；窗口不重复认识 Part/State。
var nested_inventory_data: InventoryData
## Part 指定的无状态面板 Definition。
var nested_panel_definition: InventoryPanelAssemblyDefinition
## 嵌套处理器选定的子 Host 功能 Definition。
var child_features: Array[InventoryHostFeatureDefinition] = []
## 与来源 Host 一致的业务归属实体。
var inventory_owner: Node
var initial_input_enabled := true
var initial_dependencies: Dictionary = {}
var initial_transfer_target: InventoryHost
var initial_inventory_owner: Node
var _source_host_ref: WeakRef
## 标题栏拖动状态。
var _is_dragging_title: bool = false
var _drag_offset: Vector2 = Vector2.ZERO

var _title_bar: PanelContainer
var _title_label: Label
var _close_button: Button
var _inventory_host: InventoryHost


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_apply_source_item()


## 绑定来源背包物品并刷新标题与数据。
func setup(
	item_instance: ItemInstanceData,
	nested_inventory: InventoryData,
	panel_definition: InventoryPanelAssemblyDefinition,
	features: Array[InventoryHostFeatureDefinition],
	owner_node: Node = null
) -> void:
	source_item_instance = item_instance
	nested_inventory_data = nested_inventory
	nested_panel_definition = panel_definition
	child_features = features.duplicate()
	inventory_owner = owner_node if owner_node != null else initial_inventory_owner
	initial_inventory_owner = inventory_owner
	if is_node_ready():
		_apply_source_item()


func set_source_host(host: InventoryHost) -> void:
	_source_host_ref = weakref(host) if is_instance_valid(host) else null


func get_source_host() -> InventoryHost:
	return _source_host_ref.get_ref() as InventoryHost if _source_host_ref != null else null


## 将本窗口提到同级最前。
func focus_window() -> void:
	bring_to_front_requested.emit(self)
	_clamp_to_viewport()


func get_inventory_host() -> InventoryHost:
	return _inventory_host if is_instance_valid(_inventory_host) else null


func _build_ui() -> void:
	var root_box := VBoxContainer.new()
	root_box.name = "RootBox"
	root_box.add_theme_constant_override("separation", 0)
	add_child(root_box)

	_title_bar = PanelContainer.new()
	_title_bar.name = "TitleBar"
	_title_bar.custom_minimum_size = Vector2(0, TITLE_HEIGHT)
	_title_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_title_bar.gui_input.connect(_on_title_bar_gui_input)
	root_box.add_child(_title_bar)

	var title_row := HBoxContainer.new()
	title_row.name = "TitleRow"
	title_row.add_theme_constant_override("separation", 4)
	_title_bar.add_child(title_row)

	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.text = "背包"
	title_row.add_child(_title_label)

	_close_button = Button.new()
	_close_button.name = "CloseButton"
	_close_button.text = "X"
	_close_button.custom_minimum_size = Vector2(CLOSE_BUTTON_WIDTH, TITLE_HEIGHT)
	_close_button.pressed.connect(_on_close_button_pressed)
	title_row.add_child(_close_button)

	var content_margin := MarginContainer.new()
	content_margin.name = "ContentMargin"
	content_margin.add_theme_constant_override("margin_left", int(CONTENT_MARGIN))
	content_margin.add_theme_constant_override("margin_top", int(CONTENT_MARGIN))
	content_margin.add_theme_constant_override("margin_right", int(CONTENT_MARGIN))
	content_margin.add_theme_constant_override("margin_bottom", int(CONTENT_MARGIN))
	root_box.add_child(content_margin)

	_inventory_host = InventoryHost.new()
	_inventory_host.input_enabled = initial_input_enabled
	_inventory_host.transfer_target_host = initial_transfer_target
	_inventory_host.inventory_owner = inventory_owner if inventory_owner != null else initial_inventory_owner
	for feature_type in initial_dependencies:
		_inventory_host.bind_feature_dependency(feature_type, initial_dependencies[feature_type])
	_inventory_host.definition = InventoryHostDefinition.create(
		nested_panel_definition,
		child_features
	)
	_inventory_host.name = "NestedInventoryHost"
	content_margin.add_child(_inventory_host)
	_inventory_host.ensure_inventory_panel()

	gui_input.connect(_on_window_gui_input)


## 用物品实例刷新标题与宿主背包数据。
func _apply_source_item() -> void:
	_refresh_title()
	if is_instance_valid(_inventory_host):
		_inventory_host.inventory_owner = inventory_owner
		_inventory_host.set_inventory_data(nested_inventory_data)


## Host 绑定事务完成后同步窗口元数据与标题。
func install_restored_metadata(
	item: ItemInstanceData,
	inventory: InventoryData,
	panel: InventoryPanelAssemblyDefinition,
	features: Array[InventoryHostFeatureDefinition],
	owner_node: Node = null,
	source_host: InventoryHost = null
) -> void:
	source_item_instance = item
	nested_inventory_data = inventory
	nested_panel_definition = panel
	child_features = features.duplicate()
	inventory_owner = owner_node
	set_source_host(source_host)
	_refresh_title()


func _refresh_title() -> void:
	if !is_instance_valid(source_item_instance):
		return
	var item_name := source_item_instance.get_item_name()
	if item_name.is_empty():
		item_name = "背包"
	if is_instance_valid(_title_label):
		_title_label.text = item_name


func _on_close_button_pressed() -> void:
	close_requested.emit(self)


func _on_window_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		bring_to_front_requested.emit(self)


func _on_title_bar_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_button.pressed:
			_is_dragging_title = true
			_drag_offset = get_global_mouse_position() - global_position
			bring_to_front_requested.emit(self)
		else:
			_is_dragging_title = false
		accept_event()
		return
	if event is InputEventMouseMotion and _is_dragging_title:
		global_position = get_global_mouse_position() - _drag_offset
		_clamp_to_viewport()
		accept_event()


## 将窗口限制在当前视口范围内。
func _clamp_to_viewport() -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	var viewport_rect := get_viewport_rect()
	var window_size := size
	if window_size.x <= 0.0 or window_size.y <= 0.0:
		window_size = get_combined_minimum_size()
	var max_x := maxf(viewport_rect.position.x, viewport_rect.end.x - window_size.x)
	var max_y := maxf(viewport_rect.position.y, viewport_rect.end.y - window_size.y)
	global_position = Vector2(
		clampf(global_position.x, viewport_rect.position.x, max_x),
		clampf(global_position.y, viewport_rect.position.y, max_y)
	)
