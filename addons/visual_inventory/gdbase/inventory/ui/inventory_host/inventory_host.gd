@tool
class_name InventoryHost
extends Control
## 库存使用终端：持有数据与完整 Definition，并管理布局、功能和输入的统一生命周期。
## Host 只认识通用装配协议，不识别任何具体 Part、Processor 或窗口类型。

signal mouse_pointed_item_instance(item_instance: ItemInstanceData)
## 中性配置变化通知：库存数据、Definition 或背包装配发生变化后发出。
## 转移中心等连接方订阅本信号刷新自身状态；不携带任何事件细节。
signal inventory_configuration_changed
## 中性输入上下文通知，供功能响应暂停、恢复与手持会话换绑。
signal input_context_changed

@export var inventory_data: InventoryData:
	set(value):
		inventory_data = value
		if _binding_write:
			return
		if is_node_ready():
			refresh_panel_bindings()
		_emit_configuration_changed()

@export var definition: InventoryHostDefinition:
	set(value):
		if definition == value:
			return
		var previous := definition
		definition = value
		if _binding_write:
			return
		if is_node_ready():
			_teardown_current_assembly(previous)
			ensure_inventory_panel()
		_emit_configuration_changed()

## 快捷转移去向：本 Host 作为源端的转移目标 Host。配置后 Host 在运行时自建并
## 拥有一个通用转移中心（节点不写入场景存档）；商店货架的功能装配同样以本
## 属性为客户端点。已有功能装配或手动放置的中心持有连接时，本属性让位。
@export var transfer_target_host: InventoryHost:
	set(value):
		if transfer_target_host == value:
			return
		transfer_target_host = value
		if _binding_write:
			return
		if is_node_ready():
			refresh_panel_bindings()
		_emit_configuration_changed()

## 当前绑定库存的业务所属实体；组装根赋值，Feature 以本引用解析运行时能力。
@export var inventory_owner: Node:
	set(value):
		if inventory_owner == value:
			return
		_disconnect_inventory_owner(inventory_owner)
		inventory_owner = value
		_connect_inventory_owner(inventory_owner)
		if _binding_write:
			return
		if is_node_ready():
			refresh_panel_bindings()
		_emit_configuration_changed()

## 临时暂停只影响输入，不改变功能集合或装配所有权。
var input_enabled := true:
	set(value):
		if input_enabled == value:
			return
		input_enabled = value
		_apply_bound_services()
		input_context_changed.emit()

@export_tool_button("创建背包装配") var create_action = rebuild_panel
@export_tool_button("移除背包装配") var remove_action = remove_inventory_panel

var _feature_bindings: Dictionary = {}
var _assembly: InventoryHostAssembly
var _transfer_connection: InventoryHostTransferCenter
var _owned_transfer_center: InventoryHostTransferCenter
var _bound_held_item_session: InventoryHeldItemSession
var _bound_layout: InventoryPanelAssemblyDefinition
var _scene_services: InventorySceneServices
var _binding_write := false
var _binding_transaction: InventoryHostBindingTransaction


func _ready() -> void:
	_prepare_scene_services()
	ensure_inventory_panel()
	_register_scene_services()


func _exit_tree() -> void:
	# 编辑器切换场景仅暂时离树，保留节点与装配；关闭场景时子节点随 Host 释放。
	if Engine.is_editor_hint():
		return
	if _binding_transaction != null:
		_finish_binding_transaction(_binding_transaction, false)
	_disconnect_inventory_owner(inventory_owner)
	_disconnect_layout_signals()
	_teardown_current_assembly(definition)
	if is_instance_valid(_scene_services):
		_scene_services.unregister_inventory_host(self)
	_scene_services = null


func _prepare_scene_services() -> void:
	if Engine.is_editor_hint():
		return
	_scene_services = InventorySceneServices.get_or_create(self)


func _register_scene_services() -> void:
	if _scene_services != null:
		_scene_services.register_inventory_host(self)


func set_inventory_data(inventory_data_: InventoryData) -> void:
	inventory_data = inventory_data_


func get_inventory_data() -> InventoryData:
	return inventory_data


## 成组写入库存、归属、功能依赖与转移目标后刷新一次装配。
func apply_runtime_binding(
	next_inventory: InventoryData,
	next_owner: Node,
	next_dependencies: Dictionary = {},
	next_transfer_target: InventoryHost = null
) -> void:
	_binding_write = true
	inventory_data = next_inventory
	inventory_owner = next_owner
	transfer_target_host = next_transfer_target
	_binding_write = false
	_feature_bindings = next_dependencies.duplicate()
	if is_node_ready():
		refresh_panel_bindings()
	_emit_configuration_changed()


## 输入暂停期间构建并安装候选装配，返回可认领或回退的发布记录。
## 调用方拥有跨领域门禁，完成各领域安装后调用 accept，失败调用 rollback。
func begin_binding_transaction(
	target: InventoryData,
	target_owner: Node,
	dependencies: Dictionary,
	transfer_target: InventoryHost,
	target_definition: InventoryHostDefinition = null
) -> InventoryHostBindingTransaction:
	var transaction := InventoryHostBindingTransaction.new()
	transaction.host_ref = weakref(self)
	if Engine.is_editor_hint() or not is_node_ready() or input_enabled or _binding_transaction != null:
		transaction.reason = &"host_binding_busy"
		return transaction
	var next_definition := target_definition if target_definition != null else definition
	if definition == null or next_definition == null or not definition.validate_configuration().is_empty() or not next_definition.validate_configuration().is_empty() or _assembly == null:
		transaction.reason = &"host_binding_configuration_invalid"
		return transaction
	for candidate_definition in [definition, next_definition]:
		for feature: InventoryHostFeatureDefinition in candidate_definition.features:
			var reason := feature.validate_binding_transaction()
			if reason != &"":
				transaction.reason = reason
				return transaction
	transaction.previous_inventory = inventory_data
	transaction.previous_dependencies = _feature_bindings
	transaction.previous_assembly = _assembly
	transaction.candidate_inventory = target
	transaction.candidate_dependencies = dependencies.duplicate()
	transaction.previous_transfer_target = transfer_target_host
	transaction.candidate_transfer_target = transfer_target
	transaction.previous_inventory_owner = inventory_owner
	transaction.candidate_inventory_owner = target_owner
	transaction.previous_definition = definition
	transaction.definition = next_definition
	var previous_children := get_children()
	_binding_transaction = transaction
	_binding_write = true
	definition = next_definition
	inventory_data = target
	inventory_owner = target_owner
	transfer_target_host = transfer_target
	_binding_write = false
	_feature_bindings = transaction.candidate_dependencies
	_assembly = InventoryHostAssembly.new()
	transaction.candidate_assembly = _assembly
	var built := _build_binding_assembly()
	if not built:
		transaction.reason = &"host_binding_assembly_failed"
		_finish_binding_transaction(transaction, false)
		transaction.state = InventoryHostBindingTransaction.State.FAILED
		return transaction
	transaction.preferred_size = definition.layout.get_preferred_size(_assembly.panel_assembly, _make_panel_context())
	for child in get_children():
		if previous_children.has(child):
			continue
		var entry := {&"node": child, &"process_mode": child.process_mode}
		if child is CanvasItem:
			entry[&"visible"] = child.visible
			child.hide()
		child.process_mode = Node.PROCESS_MODE_DISABLED
		transaction.candidate_nodes.append(entry)
	transaction.state = InventoryHostBindingTransaction.State.APPLIED
	return transaction


## 返回当前功能依赖表的独立容器，供管理事务构造目标绑定。
func capture_feature_dependencies() -> Dictionary:
	return _feature_bindings.duplicate()


func _build_binding_assembly() -> bool:
	var context := _make_panel_context()
	_assembly.panel_assembly = definition.layout.create_assembly(context)
	if _assembly.panel_assembly == null or not definition.layout.validate_assembly(_assembly.panel_assembly, context):
		return false
	var feature_context := _make_feature_context()
	var contributors := 0
	for feature_definition in definition.features:
		var feature := feature_definition.create_assembly(feature_context)
		if feature == null:
			return false
		feature.input_priority = feature_definition.input_priority
		_assembly.feature_assemblies.append(feature)
		_assembly.features_by_type[feature_definition.get_script()] = feature
		if feature.get_transfer_contributor() != null:
			contributors += 1
	if contributors > 1:
		return false
	for feature in _assembly.feature_assemblies:
		if not feature.refresh(feature_context):
			return false
	if not _refresh_operation_endpoint():
		return false
	_compose_input_configuration()
	var controller := get_items_input_controller()
	if controller == null:
		return _assembly.action_routes.is_empty()
	controller.input_processing_enabled = false
	controller.inventory_host = self
	controller.operation_endpoint = get_operation_endpoint()
	controller.inventory_transfer_center = get_connected_transfer_center()
	controller.held_item_session = _bound_held_item_session
	if not controller.bind_action_configuration(_assembly.action_routes, _assembly.action_observers):
		return false
	_connect_controller_signal_relays()
	return true


func _owns_binding_transaction(transaction: InventoryHostBindingTransaction) -> bool:
	return _binding_transaction == transaction and _assembly == transaction.candidate_assembly \
		and definition == transaction.definition and inventory_data == transaction.candidate_inventory \
		and inventory_owner == transaction.candidate_inventory_owner \
		and transfer_target_host == transaction.candidate_transfer_target \
		and is_same(_feature_bindings, transaction.candidate_dependencies) and not input_enabled


func _finish_binding_transaction(transaction: InventoryHostBindingTransaction, committed: bool) -> bool:
	if _binding_transaction != transaction:
		return false
	if committed:
		if not _owns_binding_transaction(transaction):
			return false
		transaction.previous_assembly.teardown(transaction.previous_definition.layout)
		_assembly.panel_assembly.size_invalidated.connect(_sync_host_preferred_size)
		for entry in transaction.candidate_nodes:
			var node: Node = entry[&"node"]
			if is_instance_valid(node):
				node.process_mode = entry[&"process_mode"]
				if node is CanvasItem:
					node.visible = entry[&"visible"]
		custom_minimum_size = transaction.preferred_size.max(Vector2.ZERO)
		transaction.state = InventoryHostBindingTransaction.State.ACCEPTED
	else:
		transaction.candidate_assembly.teardown(transaction.definition.layout)
		_assembly = transaction.previous_assembly
		_binding_write = true
		definition = transaction.previous_definition
		inventory_data = transaction.previous_inventory
		inventory_owner = transaction.previous_inventory_owner
		transfer_target_host = transaction.previous_transfer_target
		_binding_write = false
		_feature_bindings = transaction.previous_dependencies
		transaction.state = InventoryHostBindingTransaction.State.ROLLED_BACK
	_binding_transaction = null
	transaction._release_records()
	if committed:
		_sync_owned_transfer_center()
	return true


func ensure_inventory_panel() -> void:
	if definition == null or not definition.validate_configuration().is_empty():
		push_error("InventoryHost %s 配置非法: %s" % [name, definition.validate_configuration() if definition != null else &"inventory_definition_missing"])
		_disconnect_layout_signals()
		_teardown_current_assembly(definition)
		return
	_connect_layout_signals(definition.layout)
	var panel_context := _make_panel_context()
	if _assembly == null:
		var host_assembly := InventoryHostAssembly.new()
		host_assembly.panel_assembly = definition.layout.recover_assembly(panel_context)
		if host_assembly.panel_assembly == null:
			host_assembly.panel_assembly = definition.layout.create_assembly(panel_context)
		if host_assembly.panel_assembly == null or not definition.layout.validate_assembly(
			host_assembly.panel_assembly,
			panel_context
		):
			push_error("InventoryHost %s 的面板装配创建或校验失败" % name)
			host_assembly.teardown(definition.layout)
			return
		_assembly = host_assembly
		if not _create_feature_assemblies():
			_teardown_current_assembly(definition)
			return
		_compose_input_configuration()
	var panel_assembly := _assembly.panel_assembly
	if not panel_assembly.size_invalidated.is_connected(_sync_host_preferred_size):
		panel_assembly.size_invalidated.connect(_sync_host_preferred_size)
	_refresh_current_assembly(panel_context)


## 专属中心协议：转移中心把本 Host 登记为源端。同一 Host 同时最多拥有一个
## 自己的转移中心（决定其快捷转移去向），冲突明确拒绝（返回 false），
## 不采用最后写入覆盖；目标端不被注册，由中心自行引用。
func register_transfer_connection(center: InventoryHostTransferCenter) -> bool:
	if center == null:
		return false
	var current := get_connected_transfer_center()
	if current != null and current != center:
		return false
	_transfer_connection = center
	_apply_bound_services()
	return true


## 连接拥有者按拥有权释放；只解除仍属于该中心的绑定，不影响其它中心的关系。
func release_transfer_connection(center: InventoryHostTransferCenter) -> void:
	if center != null and _transfer_connection == center:
		_transfer_connection = null
		_apply_bound_services()


## 查询当前连接的转移中心；无连接或连接已失效时返回 null。
func get_connected_transfer_center() -> InventoryHostTransferCenter:
	return _transfer_connection if is_instance_valid(_transfer_connection) else null


func bind_held_item_session(session: InventoryHeldItemSession) -> void:
	_bound_held_item_session = session
	_apply_bound_services()
	input_context_changed.emit()


func get_held_item_session() -> InventoryHeldItemSession:
	if is_instance_valid(_bound_held_item_session):
		return _bound_held_item_session
	return _scene_services.get_held_item_session() if is_instance_valid(_scene_services) else null


func rebuild_panel() -> void:
	_teardown_current_assembly(definition)
	ensure_inventory_panel()
	_emit_configuration_changed()


func remove_inventory_panel() -> void:
	_teardown_current_assembly(definition)
	custom_minimum_size = Vector2.ZERO
	_emit_configuration_changed()


func refresh_panel_bindings() -> void:
	if _assembly == null:
		ensure_inventory_panel()
		return
	if definition == null or not definition.validate_configuration().is_empty():
		push_error("InventoryHost %s 配置非法: %s" % [name, definition.validate_configuration() if definition != null else &"inventory_definition_missing"])
		_teardown_current_assembly(definition)
		return
	var panel_context := _make_panel_context()
	if not definition.layout.validate_assembly(
		_assembly.panel_assembly,
		panel_context
	):
		rebuild_panel()
		return
	_refresh_current_assembly(panel_context)


func get_assembly_part(type: Script) -> Node:
	return (
		_assembly.panel_assembly.get_part(type)
		if _assembly != null and _assembly.panel_assembly != null
		else null
	)


func get_assembly_parts() -> Array[Node]:
	return (
		_assembly.panel_assembly.get_parts()
		if _assembly != null and _assembly.panel_assembly != null
		else []
	)


func find_assembly_part_with_method(method: StringName) -> Node:
	return (
		_assembly.panel_assembly.find_part_with_method(method)
		if _assembly != null and _assembly.panel_assembly != null
		else null
	)


func get_items_input_controller() -> InventoryItemsInputController:
	return (
		_assembly.panel_assembly.get_input_controller()
		if _assembly != null and _assembly.panel_assembly != null
		else null
	)


## 读取当前布局的单位格像素尺寸；无布局时返回默认 48×48。
func get_cell_size() -> Vector2:
	if definition != null and definition.layout != null:
		return definition.layout.cell_size
	return Vector2(48, 48)


func _make_panel_context() -> InventoryPanelAssemblyContext:
	return InventoryPanelAssemblyContext.new(
		self,
		inventory_data,
		get_cell_size(),
		owner,
		_scene_services
	)


func _make_feature_context() -> InventoryHostFeatureContext:
	return InventoryHostFeatureContext.new(
		self,
		inventory_data,
		inventory_owner,
		_assembly.panel_assembly,
		get_items_input_controller(),
		_scene_services,
		Engine.is_editor_hint()
	)


func _connect_inventory_owner(owner_node: Node) -> void:
	if not is_instance_valid(owner_node):
		return
	if not owner_node.tree_exiting.is_connected(_on_inventory_owner_tree_exiting):
		owner_node.tree_exiting.connect(_on_inventory_owner_tree_exiting)


func _disconnect_inventory_owner(owner_node: Node) -> void:
	if not is_instance_valid(owner_node):
		return
	if owner_node.tree_exiting.is_connected(_on_inventory_owner_tree_exiting):
		owner_node.tree_exiting.disconnect(_on_inventory_owner_tree_exiting)


## 归属离树后使操作端点失效并释放依赖订阅，组装根再次入树后显式重绑。
func _on_inventory_owner_tree_exiting() -> void:
	_disconnect_inventory_owner(inventory_owner)
	var endpoint := get_operation_endpoint()
	if endpoint != null:
		endpoint.invalidate()
	_feature_bindings.clear()
	if _binding_write:
		return
	if is_node_ready():
		refresh_panel_bindings()
	_emit_configuration_changed()


func _create_feature_assemblies() -> bool:
	var context := _make_feature_context()
	for feature_definition in definition.features:
		if feature_definition == null:
			push_error("InventoryHost %s 包含空功能 Definition" % name)
			return false
		if Engine.is_editor_hint() and not feature_definition.can_assemble_in_editor():
			continue
		var feature_assembly := feature_definition.create_assembly(context)
		if feature_assembly == null:
			push_error("InventoryHost %s 功能装配创建失败" % name)
			return false
		feature_assembly.input_priority = feature_definition.input_priority
		_assembly.feature_assemblies.append(feature_assembly)
		_assembly.features_by_type[feature_definition.get_script()] = feature_assembly
	var contributor_count := 0
	for feature in _assembly.feature_assemblies:
		if feature.get_transfer_contributor() != null:
			contributor_count += 1
	if contributor_count > 1:
		push_error("inventory_transfer_contributor_duplicate")
		return false
	return true

## 返回当前 Host 独占的转移贡献者。
func get_transfer_contributor() -> InventoryHostTransferContributor:
	if _assembly == null:
		return null
	for feature in _assembly.feature_assemblies:
		var contributor := feature.get_transfer_contributor()
		if contributor != null:
			return contributor
	return null


func _compose_input_configuration() -> void:
	_assembly.action_routes = InventoryInputConfigurationComposer.compose_routes(
		_assembly.feature_assemblies
	)
	_assembly.action_observers = InventoryInputConfigurationComposer.compose_observers(
		_assembly.feature_assemblies
	)


func _refresh_current_assembly(panel_context: InventoryPanelAssemblyContext) -> void:
	if inventory_data != null:
		inventory_data.ensure_occupancy_synced()
		if !Engine.is_editor_hint():
			# 反序列化的实例必须在接收输入前准备必需 State，不能等规划复制时才补齐。
			for item in inventory_data.get_item_instances():
				item._ensure_instance_states_ready()
	definition.layout.refresh_assembly(_assembly.panel_assembly, panel_context)
	var feature_context := _make_feature_context()
	for feature_assembly in _assembly.feature_assemblies:
		if not feature_assembly.refresh(feature_context):
			push_error("InventoryHost 功能换绑失败")
			_teardown_current_assembly(definition)
			return
	if not _refresh_operation_endpoint():
		_teardown_current_assembly(definition)
		return
	_connect_controller_signal_relays()
	_apply_bound_services()
	_sync_owned_transfer_center()
	_sync_host_preferred_size()


func _teardown_current_assembly(host_definition: InventoryHostDefinition) -> void:
	if _assembly == null:
		return
	var panel_assembly := _assembly.panel_assembly
	if panel_assembly != null and panel_assembly.size_invalidated.is_connected(
		_sync_host_preferred_size
	):
		panel_assembly.size_invalidated.disconnect(_sync_host_preferred_size)
	var panel_definition := (
		host_definition.layout if host_definition != null else null
	)
	_assembly.teardown(panel_definition)
	_assembly = null


## 订阅布局资源变化，使格子尺寸等作者参数变更后刷新装配。
func _connect_layout_signals(layout: InventoryPanelAssemblyDefinition) -> void:
	if _bound_layout == layout:
		return
	_disconnect_layout_signals()
	_bound_layout = layout
	if _bound_layout != null and not _bound_layout.changed.is_connected(_on_layout_resource_changed):
		_bound_layout.changed.connect(_on_layout_resource_changed)


func _disconnect_layout_signals() -> void:
	if _bound_layout != null and is_instance_valid(_bound_layout) \
			and _bound_layout.changed.is_connected(_on_layout_resource_changed):
		_bound_layout.changed.disconnect(_on_layout_resource_changed)
	_bound_layout = null


func _on_layout_resource_changed() -> void:
	if _binding_write or not is_node_ready():
		return
	refresh_panel_bindings()


func _apply_bound_services() -> void:
	var controller := get_items_input_controller()
	if controller == null:
		if _assembly != null and not _assembly.action_routes.is_empty():
			push_error("InventoryHost: 布局未提供功能输入所需的目标解析控制器")
			_teardown_current_assembly(definition)
		return
	controller.input_processing_enabled = input_enabled and _assembly != null and not _assembly.action_routes.is_empty()
	controller.inventory_host = self
	controller.operation_endpoint = get_operation_endpoint()
	controller.inventory_transfer_center = get_connected_transfer_center()
	controller.held_item_session = _bound_held_item_session
	if _assembly != null:
		if not controller.bind_action_configuration(
			_assembly.action_routes,
			_assembly.action_observers
		):
			controller.input_processing_enabled = false
			_teardown_current_assembly(definition)


func _connect_controller_signal_relays() -> void:
	var controller := get_items_input_controller()
	if controller == null:
		return
	if not controller.mouse_pointed_item_instance.is_connected(
		_relay_mouse_pointed_item_instance
	):
		controller.mouse_pointed_item_instance.connect(
			_relay_mouse_pointed_item_instance
		)


func _relay_mouse_pointed_item_instance(item_instance: ItemInstanceData) -> void:
	mouse_pointed_item_instance.emit(item_instance)


func _sync_host_preferred_size() -> void:
	if definition == null or definition.layout == null or _assembly == null:
		custom_minimum_size = Vector2.ZERO
		return
	var preferred_size := definition.layout.get_preferred_size(
		_assembly.panel_assembly,
		_make_panel_context()
	)
	custom_minimum_size = Vector2(
		maxf(preferred_size.x, 0.0),
		maxf(preferred_size.y, 0.0)
	)


## 组装根显式注入功能运行时依赖；不写入共享 Definition。
func bind_feature_dependency(type: Script, dependency: Object) -> void:
	if dependency == null:
		_feature_bindings.erase(type)
	else:
		_feature_bindings[type] = dependency
	if is_node_ready():
		refresh_panel_bindings()


func get_feature_dependency(type: Script) -> Object:
	var dependency = _feature_bindings.get(type)
	return dependency if is_instance_valid(dependency) else null


func is_assembled() -> bool:
	return _assembly != null


func _emit_configuration_changed() -> void:
	if is_node_ready():
		inventory_configuration_changed.emit()


## 运行时依据 transfer_target_host 维护本 Host 自有的通用转移中心。
## 目标有效且连接空闲时创建并绑定，目标清空或非法时释放。
## 外部已注册中心持有源端连接时保留其拥有权，自动中心随 Host 生命周期管理。
func _sync_owned_transfer_center() -> void:
	if Engine.is_editor_hint():
		return
	var target := transfer_target_host if is_instance_valid(transfer_target_host) else null
	if target == null or target == self:
		if _owned_transfer_center != null:
			var center := _owned_transfer_center
			_owned_transfer_center = null
			center.clear_host_binding()
			center.queue_free()
		return
	var connected := get_connected_transfer_center()
	if connected != null and connected != _owned_transfer_center:
		return
	if _owned_transfer_center == null or not is_instance_valid(_owned_transfer_center):
		_owned_transfer_center = InventoryHostTransferCenter.new()
		_owned_transfer_center.name = "InventoryTransferCenter"
		add_child(_owned_transfer_center)
	_owned_transfer_center.bind_hosts(self, target)


## 按具体功能脚本取得本 Host 的运行时装配。
func get_feature_assembly(type: Script) -> InventoryHostFeatureAssembly:
	return _assembly.features_by_type.get(type) if _assembly != null else null

func get_operation_endpoint() -> InventoryOperationEndpoint:
	return _assembly.operation_endpoint if _assembly != null else null

func _refresh_operation_endpoint() -> bool:
	var endpoint := _assembly.operation_endpoint
	if endpoint != null and endpoint.inventory == inventory_data:
		return true
	if endpoint != null:
		endpoint.invalidate()
	var policies: Array = []
	for feature in _assembly.feature_assemblies:
		var policy := feature.get_operation_policy()
		if policy != null:
			policies.append(policy)
	_assembly.operation_endpoint = InventoryOperationEndpoint.create(
		inventory_data, InventoryOperationPolicy.merge(policies)
	)
	return true
