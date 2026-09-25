class_name NestedInventoryWindowService
extends CanvasLayer
## 场景级嵌套窗口服务；由通用 InventorySceneServices 按租约唯一持有。

const WINDOW_CASCADE_OFFSET := Vector2(28, 28)
const BASE_WINDOW_Z_INDEX := 120

var _windows_by_item: Dictionary = {}
var _require_membership_by_item: Dictionary = {}
var _next_window_index: int = 0
var animation_resolver: Callable
var _animation_handles: Array[ItemAnimationPlaybackHandle] = []
var _tearing_down := false
var _appearance_generations: Dictionary = {}
var last_animation_result: ItemAnimationPlaybackHandle


func _ready() -> void:
	set_process(true)


func _exit_tree() -> void:
	_tearing_down = true
	close_all(false)
	for handle in _animation_handles:
		handle.cancel()
	_animation_handles.clear()
	animation_resolver = Callable()


func _process(_delta: float) -> void:
	_purge_invalid_windows()
	_close_stale_context_windows()
	_close_inaccessible_windows()


func open_for_item(
	item_instance: ItemInstanceData,
	nested_inventory: InventoryData,
	panel_definition: InventoryPanelAssemblyDefinition,
	child_features: Array[InventoryHostFeatureDefinition],
	owner_node: Node = null,
	source_host: InventoryHost = null
) -> NestedInventoryWindow:
	if not is_instance_valid(item_instance) or nested_inventory == null or panel_definition == null:
		return null
	_purge_invalid_windows()
	var existing_window := _windows_by_item.get(item_instance) as NestedInventoryWindow
	if is_instance_valid(existing_window):
		if (
			existing_window.nested_inventory_data == nested_inventory
			and existing_window.nested_panel_definition == panel_definition
			and existing_window.child_features == child_features
			and existing_window.inventory_owner == owner_node
		):
			_bring_window_to_front(existing_window)
			existing_window.focus_window()
			return existing_window
		_close_window(existing_window)
	var window := NestedInventoryWindow.new()
	window.name = "NestedInventoryWindow"
	window.initial_inventory_owner = owner_node
	window.set_source_host(source_host)
	window.setup(item_instance, nested_inventory, panel_definition, child_features, owner_node)
	window.close_requested.connect(_on_window_close_requested)
	window.bring_to_front_requested.connect(_on_window_bring_to_front_requested)
	add_child(window)
	if not window.get_inventory_host().is_assembled():
		window.queue_free()
		return null
	_windows_by_item[item_instance] = window
	_require_membership_by_item[item_instance] = _is_item_accessible(item_instance)
	window.tree_exiting.connect(_on_window_exiting.bind(window), CONNECT_ONE_SHOT)
	_set_window_appearance(item_instance, true)
	window.global_position = _get_next_window_position()
	_bring_window_to_front(window)
	window.call_deferred("_clamp_to_viewport")
	return window


func close_for_item(item_instance: ItemInstanceData) -> void:
	var window := _windows_by_item.get(item_instance) as NestedInventoryWindow
	if is_instance_valid(window):
		_close_window(window)


func close_all(animate := true) -> void:
	for window in _windows_by_item.values():
		if is_instance_valid(window):
			_close_window(window as NestedInventoryWindow, animate)
	_windows_by_item.clear()
	_require_membership_by_item.clear()
	_next_window_index = 0


func get_window_for_item(item_instance: ItemInstanceData) -> NestedInventoryWindow:
	var window := _windows_by_item.get(item_instance) as NestedInventoryWindow
	return window if is_instance_valid(window) else null


## 在同步管理门禁下准备窗口换绑，原服务索引保持至认领。
func begin_restore_window(
	existing: NestedInventoryWindow,
	item: ItemInstanceData,
	inventory: InventoryData,
	panel: InventoryPanelAssemblyDefinition,
	features: Array[InventoryHostFeatureDefinition],
	dependencies: Dictionary,
	transfer_target: InventoryHost,
	owner_node: Node = null,
	source_host: InventoryHost = null
) -> NestedInventoryWindowRestore:
	var restore := NestedInventoryWindowRestore.new()
	restore.service_ref = weakref(self)
	var definition := InventoryHostDefinition.create(panel, features)
	if _tearing_down or not is_inside_tree() or item == null or inventory == null or not definition.validate_configuration().is_empty():
		restore.reason = &"nested_restore_configuration_invalid"
		return restore
	if existing != null and (not is_instance_valid(existing) or get_window_for_item(existing.source_item_instance) != existing):
		restore.reason = &"nested_restore_window_stale"
		return restore
	var collision := get_window_for_item(item)
	if collision != null and collision != existing:
		restore.reason = &"nested_restore_item_collision"
		return restore
	restore.target_item = item
	restore.target_inventory = inventory
	restore.target_panel = panel
	restore.target_features = features.duplicate()
	restore.target_owner = owner_node
	restore.target_source_host = source_host
	restore.created = existing == null
	if restore.created:
		restore.window = NestedInventoryWindow.new()
		restore.window.initial_input_enabled = false
		restore.window.initial_dependencies = dependencies.duplicate()
		restore.window.initial_transfer_target = transfer_target
		restore.window.initial_inventory_owner = owner_node
		restore.window.set_source_host(source_host)
		restore.window.setup(item, inventory, panel, features, owner_node)
		restore.window.hide()
		restore.window.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(restore.window)
		if not restore.window.get_inventory_host().is_assembled():
			restore.window.free()
			restore.reason = &"nested_restore_assembly_failed"
			return restore
	else:
		restore.window = existing
		restore.original_item = existing.source_item_instance
		restore.host_transaction = existing.get_inventory_host().begin_binding_transaction(inventory, owner_node, dependencies, transfer_target, definition)
		if not restore.host_transaction.is_applied():
			restore.reason = restore.host_transaction.reason
			return restore
	restore.state = NestedInventoryWindowRestore.State.APPLIED
	return restore


## 认领已准备的窗口及服务索引，调用方统一恢复输入资格。
func accept_restored_window(restore: NestedInventoryWindowRestore) -> bool:
	if restore.service_ref.get_ref() != self or not restore.preflight():
		return false
	var window := restore.window
	if restore.host_transaction != null and not restore.host_transaction.accept(false):
		return false
	if restore.created:
		window.close_requested.connect(_on_window_close_requested)
		window.bring_to_front_requested.connect(_on_window_bring_to_front_requested)
		window.tree_exiting.connect(_on_window_exiting.bind(window), CONNECT_ONE_SHOT)
		window.global_position = _get_next_window_position()
	else:
		_windows_by_item.erase(restore.original_item)
		_require_membership_by_item.erase(restore.original_item)
	window.install_restored_metadata(
		restore.target_item,
		restore.target_inventory,
		restore.target_panel,
		restore.target_features,
		restore.target_owner,
		restore.target_source_host
	)
	_windows_by_item[restore.target_item] = window
	_require_membership_by_item[restore.target_item] = _is_item_accessible(restore.target_item)
	window.process_mode = Node.PROCESS_MODE_INHERIT
	window.show()
	_bring_window_to_front(window)
	restore.state = NestedInventoryWindowRestore.State.ACCEPTED
	return true


func _on_window_close_requested(window: NestedInventoryWindow) -> void:
	_close_window(window)


func _on_window_bring_to_front_requested(window: NestedInventoryWindow) -> void:
	_bring_window_to_front(window)


func _close_window(window: NestedInventoryWindow, animate := true) -> void:
	if not is_instance_valid(window):
		return
	var source_item := window.source_item_instance
	if source_item != null and _windows_by_item.get(source_item) == window:
		_windows_by_item.erase(source_item)
		_require_membership_by_item.erase(source_item)
		_set_window_appearance(source_item, false, animate)
	window.process_mode = Node.PROCESS_MODE_DISABLED
	if window.get_inventory_host() != null:
		window.get_inventory_host().input_enabled = false
	window.queue_free()


func _bring_window_to_front(window: NestedInventoryWindow) -> void:
	if not is_instance_valid(window) or window.get_parent() != self:
		return
	move_child(window, get_child_count() - 1)
	window.z_index = BASE_WINDOW_Z_INDEX + get_child_count()


func _purge_invalid_windows() -> void:
	var stale_items: Array = []
	for item_instance in _windows_by_item.keys():
		var window := _windows_by_item.get(item_instance) as NestedInventoryWindow
		if not is_instance_valid(item_instance) or not is_instance_valid(window):
			stale_items.append(item_instance)
			if is_instance_valid(window):
				window.queue_free()
	for stale_item in stale_items:
		_windows_by_item.erase(stale_item)
		_require_membership_by_item.erase(stale_item)
		if is_instance_valid(stale_item):
			_set_window_appearance(stale_item, false)


func _close_inaccessible_windows() -> void:
	for item_instance in _windows_by_item.keys().duplicate():
		if _is_item_accessible(item_instance):
			_require_membership_by_item[item_instance] = true
			continue
		# 目录/调试入口可打开从未属于库存的临时实例；只有曾经可达的来源
		# 离开全部库存和手持会话后才自动关闭。
		if not bool(_require_membership_by_item.get(item_instance, false)):
			continue
		var window := _windows_by_item.get(item_instance) as NestedInventoryWindow
		if is_instance_valid(window):
			_close_window(window)


## 来源 Host 离树或换归属、物品离开原归属上下文时关闭旧窗口。
func _close_stale_context_windows() -> void:
	for item_instance in _windows_by_item.keys().duplicate():
		var window := _windows_by_item.get(item_instance) as NestedInventoryWindow
		if not is_instance_valid(window):
			continue
		var source_host := window.get_source_host()
		if source_host != null:
			if not is_instance_valid(source_host) or not source_host.is_inside_tree() or source_host.is_queued_for_deletion():
				_close_window(window)
				continue
			if source_host.inventory_owner != window.inventory_owner:
				_close_window(window)
				continue
		if window.inventory_owner != null and not _is_reachable_under_owner(item_instance, window.inventory_owner):
			_close_window(window)


func _is_reachable_under_owner(target: ItemInstanceData, owner_node: Node) -> bool:
	var services := get_parent() as InventorySceneServices
	if services == null or not is_instance_valid(owner_node):
		return false
	if services.get_held_item_session().get_held_item() == target:
		return true
	var visited_inventories: Dictionary = {}
	for host in services.get_registered_hosts():
		if host.inventory_owner != owner_node:
			continue
		if _inventory_contains_recursive(host.get_inventory_data(), target, visited_inventories):
			return true
	return false


func _is_item_accessible(item_instance: ItemInstanceData) -> bool:
	var services := get_parent() as InventorySceneServices
	if services == null:
		return false
	if services.get_held_item_session().get_held_item() == item_instance:
		return true
	return _is_reachable_from_registered_host(item_instance, services)


func _is_reachable_from_registered_host(
	target: ItemInstanceData,
	services: InventorySceneServices
) -> bool:
	var visited_inventories: Dictionary = {}
	for host in services.get_registered_hosts():
		var inventory := host.get("inventory_data") as InventoryData
		if _inventory_contains_recursive(inventory, target, visited_inventories):
			return true
	return false


func _inventory_contains_recursive(
	inventory: InventoryData,
	target: ItemInstanceData,
	visited: Dictionary
) -> bool:
	if inventory == null or visited.has(inventory):
		return false
	visited[inventory] = true
	for item in inventory.get_item_instances():
		if item == target:
			return true
		if item == null or item.item_data == null:
			continue
		var ownership := NestedInventoryQuery.query_owned_inventories(item)
		if not ownership.valid:
			continue
		for child_inventory in ownership.inventories:
			if _inventory_contains_recursive(child_inventory, target, visited):
				return true
	return false


func _get_next_window_position() -> Vector2:
	var viewport := get_viewport()
	var base_position := Vector2(64, 64)
	if is_instance_valid(viewport):
		base_position = viewport.get_mouse_position() + Vector2(16, 16)
	var cascaded := base_position + WINDOW_CASCADE_OFFSET * float(_next_window_index)
	_next_window_index += 1
	return cascaded


func _on_window_exiting(window: NestedInventoryWindow) -> void:
	var item := window.source_item_instance
	if _windows_by_item.get(item) == window:
		_windows_by_item.erase(item)
		_require_membership_by_item.erase(item)
		_set_window_appearance(item, false, not _is_shutting_down())

func _set_window_appearance(item: ItemInstanceData, opened: bool, animate := true) -> void:
	var animation_processor := animation_resolver.call() as ItemAnimationProcessor if animation_resolver.is_valid() else null
	last_animation_result = null
	if not is_instance_valid(animation_processor) or item == null:
		return
	_animation_handles = _animation_handles.filter(func(handle): return not handle.is_finished())
	var appearance: StringName = &"opened" if opened else &"closed"
	if not animate:
		# 同帧重新装配的新窗口已接受目标时，旧服务退出不得再写关闭态。
		var prior: Dictionary = _appearance_generations.get(item.get_instance_id(), {})
		if prior.is_empty() or prior.processor.get_ref() != animation_processor or animation_processor.get_appearance_generation(item) != prior.generation:
			return
		animation_processor.set_appearance(item, appearance)
		return
	last_animation_result = animation_processor.transition_to(item, appearance, &"open" if opened else &"close")
	_appearance_generations[item.get_instance_id()] = {"processor": weakref(animation_processor), "generation": animation_processor.get_appearance_generation(item)}
	if not last_animation_result.is_finished():
		_animation_handles.append(last_animation_result)

func _is_shutting_down() -> bool:
	if _tearing_down:
		return true
	var node: Node = self
	while node != null:
		if node.is_queued_for_deletion():
			return true
		node = node.get_parent()
	return false
