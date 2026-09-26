@tool
extends SubViewportContainer
const Catalog = preload("res://addons/visual_inventory/inventory_host_definition/inventory_host_layout_editor_catalog.gd")
const OrbitAdapter = preload("res://addons/visual_inventory/inventory_host_definition/orbit_layout_preview_adapter.gd")
const DEFAULT_INVENTORY_PATH := "res://addons/visual_inventory/inventory_host_definition/default_preview_inventory.tres"
const SAMPLE_FOLDER := "res://addons/visual_inventory/inventory_host_definition/catalog_samples"
signal validation_changed(problem: String)
var viewport: SubViewport
var mount: Control
var assembly: InventoryPanelAssembly
var context: InventoryPanelAssemblyContext
var layout: InventoryPanelAssemblyDefinition
var inventory: InventoryData
var adapter: Node
var cell_pixels := 48.0
var view_zoom := 1.0
var problem := ""
var _pending_layout: InventoryPanelAssemblyDefinition
var _queued := false
var _closed := false
var _generation := 0
var _inventory_changed := true

func _init() -> void:
	stretch = true
	# 随编辑器窗口收缩；过大最小值会顶破三列布局。
	custom_minimum_size = Vector2.ZERO
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP

func _ready() -> void:
	viewport = SubViewport.new()
	viewport.name = "LayoutPreviewViewport"
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.handle_input_locally = true
	add_child(viewport)
	mount = Control.new()
	mount.name = "PreviewLayout"
	viewport.add_child(mount)
	adapter = OrbitAdapter.new()
	viewport.add_child(adapter)
	resized.connect(_position_mount)
	mouse_exited.connect(adapter.cancel_pointer)
	get_window().focus_exited.connect(stop)
	if inventory == null:
		inventory = create_sample()
	_position_mount()

static func create_sample() -> InventoryData:
	var source := load(DEFAULT_INVENTORY_PATH) as InventoryData
	if source == null:
		push_error("布局预览背包资源无法加载：" + DEFAULT_INVENTORY_PATH)
		return null
	var data := source.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as InventoryData
	# 外部物品模板也要隔离；只读图标沿用源纹理，避免复制导入纹理。
	var source_items := source.get_item_instances()
	var preview_items := data.get_item_instances()
	for index in preview_items.size():
		if preview_items[index].item_data != null:
			preview_items[index].item_data.icon = source_items[index].get_item_icon()
	data.ensure_occupancy_synced()
	return data

func reset_sample() -> void:
	inventory = create_sample()
	_inventory_changed = true
	request_layout(_pending_layout)

func request_layout(value: InventoryPanelAssemblyDefinition) -> void:
	_pending_layout = value
	if _queued or _closed:
		return
	_queued = true
	call_deferred("_refresh")

func _refresh() -> void:
	_queued = false
	if _closed or not is_inside_tree() or mount == null:
		return
	_generation += 1
	problem = Catalog.validate(_pending_layout)
	if inventory == null:
		problem = "默认预览背包资源无法加载。"
	if not problem.is_empty():
		clear_assembly()
		validation_changed.emit(problem)
		return
	adapter.stop()
	var next := Catalog.clone_layout(_pending_layout)
	if next is ResourceScanCatalogInventoryPanelAssemblyDefinition:
		next.scan_folder = SAMPLE_FOLDER
	var rebuild: bool = assembly == null or _inventory_changed or layout.get_script() != next.get_script()
	if layout is GridInventoryPanelAssemblyDefinition and next is GridInventoryPanelAssemblyDefinition:
		rebuild = (
			rebuild
			or layout.create_background != next.create_background
			or layout.create_grid_panel != next.create_grid_panel
			or layout.create_items_panel != next.create_items_panel
		)
	if Catalog.type_index(next) < 0:
		rebuild = true
	if rebuild:
		clear_assembly()
	layout = next
	context = InventoryPanelAssemblyContext.new(mount, inventory, Vector2.ONE * cell_pixels, null)
	if assembly == null:
		assembly = layout.create_assembly(context)
	else:
		layout.refresh_assembly(assembly, context)
	if assembly != null and not layout.validate_assembly(assembly, context):
		layout.teardown_assembly(assembly)
		assembly = null
	if assembly == null:
		problem = "布局装配失败，请检查脚本与编辑器错误输出。"
		for child in mount.get_children():
			mount.remove_child(child)
			child.queue_free()
	else:
		_clear_owners(mount)
		var controller := assembly.get_input_controller()
		if controller != null:
			controller.input_processing_enabled = false
			controller.set_process_input(false)
			controller.set_process_unhandled_input(false)
		if not assembly.size_invalidated.is_connected(_position_mount):
			assembly.size_invalidated.connect(_position_mount)
		var track := assembly.get_part(OrbitTrack) as OrbitTrack
		if track != null:
			adapter.attach(track)
			if rebuild and track.deal_auto_play:
				call_deferred("_play_initial", _generation)
		_position_mount()
	_inventory_changed = false
	validation_changed.emit(problem)

func _clear_owners(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		_clear_owners(child)

func _play_initial(generation: int) -> void:
	if generation == _generation and not _closed:
		play_deal()

func _position_mount() -> void:
	if mount == null or viewport == null:
		return
	var desired := Vector2(384, 288)
	if assembly != null and layout != null:
		desired = layout.get_preferred_size(assembly, context).max(Vector2.ONE)
	mount.size = desired
	# Zoom is a viewport transform; pointer coordinates stay in the layout's canvas.
	viewport.canvas_transform = Transform2D(0.0, Vector2.ONE * view_zoom, 0.0, (size - desired * view_zoom) * 0.5)
	mount.position = Vector2.ZERO

func play_deal() -> void:
	if assembly == null:
		return
	var track := assembly.get_part(OrbitTrack) as OrbitTrack
	if track != null:
		adapter.playing = true
		track.preview_play()

func add_sample() -> bool:
	if assembly == null or inventory == null or inventory.get_item_instances().is_empty():
		return false
	var item := inventory.get_item_instances()[0].duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as ItemInstanceData
	if not inventory.occupy_map.try_register_item_instance_at_free_cell(item, false):
		return false
	inventory.ensure_occupancy_synced()
	var track := assembly.get_part(OrbitTrack) as OrbitTrack
	if track != null and track.entrance_on_child_added:
		call_deferred("_play_added", item, _generation)
	return true

func _play_added(item: ItemInstanceData, generation: int) -> void:
	if generation != _generation or _closed or assembly == null:
		return
	var track := assembly.get_part(OrbitTrack) as OrbitTrack
	var panel := assembly.get_part(FreeItemsPanel) as FreeItemsPanel
	if track == null or panel == null:
		return
	for cell in panel.get_cells():
		if cell.get("item_instance_data") == item:
			track.play_entrance_animation(cell)

func remove_sample() -> void:
	if inventory != null and not inventory.get_item_instances().is_empty():
		var item: ItemInstanceData = inventory.get_item_instances().back()
		inventory.occupy_map.try_remove_item_instance(item)
		inventory.ensure_occupancy_synced()

func stop() -> void:
	if is_instance_valid(adapter):
		adapter.stop()

func clear_assembly() -> void:
	stop()
	if assembly != null:
		layout.teardown_assembly(assembly)
	assembly = null
	layout = null
	context = null

func shutdown() -> void:
	_closed = true
	_generation += 1
	clear_assembly()

func _exit_tree() -> void:
	shutdown()
