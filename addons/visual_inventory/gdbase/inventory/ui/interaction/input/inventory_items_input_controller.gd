@tool
class_name InventoryItemsInputController
extends Node
## 库存输入控制器：物理输入只映射为稳定动作 ID，业务语义由 Route/Processor 执行。
##
## 分发契约：路由链按功能 input_priority 降序合并，逐处理器执行——PASS 继续、
## HANDLED/REJECTED 消费输入终止链，观察器在链前后成对执行。
## 三个入口：指针事件（GUI 面板转发）、键盘/手柄（场景级 Router 调
## handle_routed_input）、语义直发（UI/测试用 dispatch_action_for_target，
## 不受物理映射约束）。

const GROUP_NAME := "InventoryItemsInputController"


signal operation_feedback_requested(item: ItemInstanceData)

signal mouse_pointed_item_instance(item_instance: ItemInstanceData)

@export var inventory_data: InventoryData
@export var inventory_grid_panel: InventoryGridPanel
@export var held_item_view_parent: Node
@export var held_item_session: InventoryHeldItemSession
## 当前连接的转移中心；由 InventoryHost 装配时下发。
@export var inventory_transfer_center: InventoryHostTransferCenter
## 所属宿主；由 InventoryHost 装配时下发，转移中心凭它确定调用方端点。
var inventory_host: InventoryHost
@export var input_processing_enabled: bool = true:
	set(value):
		input_processing_enabled = value
		if !value:
			deactivate_input()

var _pointer_observers: Dictionary[int, WeakRef] = {}

## 被动功能可观察指针目标，不获得动作输入或活动路由器所有权。
func set_pointer_observer(observer: Object, enabled: bool) -> void:
	if observer == null:
		return
	if enabled:
		_pointer_observers[observer.get_instance_id()] = weakref(observer)
	else:
		_pointer_observers.erase(observer.get_instance_id())
	if not is_pointer_tracking_enabled():
		_last_pointed_item_instance = null

func is_pointer_tracking_enabled() -> bool:
	if input_processing_enabled:
		return true
	for observer: WeakRef in _pointer_observers.values():
		if observer.get_ref() != null:
			return true
	return false

var _last_pointed_item_instance: ItemInstanceData
var _last_target_cell := Vector2i(-1, -1)
var _last_source_grid_panel: InventoryGridPanel
var _operation_inventory_data: InventoryData
var operation_endpoint: InventoryOperationEndpoint
var _operation_grid_panel: InventoryGridPanel
var _routes_by_action: Dictionary[StringName, InventoryInputActionRoute] = {}
var _action_observers: Array[InventoryInputActionObserver] = []


func _ready() -> void:
	add_to_group(GROUP_NAME)
	_try_bind_inventory_grid_panel()


func _exit_tree() -> void:
	deactivate_input()


static func find_for_inventory(
	from_node: Node,
	target_inventory_data: InventoryData
) -> InventoryItemsInputController:
	if !is_instance_valid(from_node) or !from_node.is_inside_tree():
		return null
	if target_inventory_data == null:
		return null
	for controller_node in from_node.get_tree().get_nodes_in_group(GROUP_NAME):
		if controller_node is InventoryItemsInputController:
			var controller := controller_node as InventoryItemsInputController
			if controller.input_processing_enabled and controller.inventory_data == target_inventory_data:
				return controller
	return null


func bind_action_configuration(
	routes: Array[InventoryInputActionRoute],
	observers: Array[InventoryInputActionObserver]
) -> bool:
	var new_index: Dictionary[StringName, InventoryInputActionRoute] = {}
	for route in routes:
		if route == null:
			push_error("库存输入 Route 不得为空")
			return false
		if route.action_id.is_empty():
			push_error("库存输入 Route action_id 不得为空")
			return false
		if new_index.has(route.action_id):
			push_error("库存输入 Route action_id 重复: %s" % route.action_id)
			return false
		if route.processors.is_empty():
			push_error("库存输入 Route %s 至少需要一个 Processor" % route.action_id)
			return false
		for processor in route.processors:
			if processor == null:
				push_error("库存输入 Route %s 包含空 Processor" % route.action_id)
				return false
		new_index[route.action_id] = route
	for observer in observers:
		if observer == null:
			push_error("库存输入 Observer 不得为空")
			return false
	_routes_by_action = new_index
	_action_observers = observers.duplicate()
	return true


func get_configured_action_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for action_id: StringName in _routes_by_action.keys():
		ids.append(action_id)
	return ids


func _try_bind_inventory_grid_panel() -> void:
	if is_instance_valid(inventory_grid_panel):
		inventory_grid_panel.bind_items_input_controller(self)


func _get_held_item_session() -> InventoryHeldItemSession:
	if is_instance_valid(held_item_session):
		return held_item_session
	var services := InventorySceneServices.get_or_create(self)
	if services == null:
		return null
	var session := services.get_held_item_session()
	if session != null and is_instance_valid(held_item_view_parent):
		session.preferred_view_parent = held_item_view_parent
	return session


func _find_held_item_session() -> InventoryHeldItemSession:
	if is_instance_valid(held_item_session):
		return held_item_session
	var services := InventorySceneServices.find_existing(self)
	return services.get_held_item_session() if services != null else null


## GUI 面板转发的通用输入入口。
func handle_pointer_input(
	event: InputEvent,
	source_grid_panel: InventoryGridPanel = null
) -> bool:
	if !input_processing_enabled or event == null:
		return false
	var action_id := InventoryInputActionIds.from_event(event)
	if action_id.is_empty() or !_routes_by_action.has(action_id):
		return false
	if !_is_pointer_action_available(source_grid_panel):
		return false
	activate_input(source_grid_panel)
	_begin_grid_operation(source_grid_panel)
	var result := _dispatch_action_with_operation_context(action_id)
	_end_grid_operation()
	return result.consumes_input()


## 场景级 Router 的键盘/手柄入口。
func handle_routed_input(event: InputEvent) -> InventoryInputActionResult:
	if !input_processing_enabled or event == null:
		return InventoryInputActionResult.pass_result()
	var action_id := InventoryInputActionIds.from_event(event)
	if action_id.is_empty() or !_routes_by_action.has(action_id):
		return InventoryInputActionResult.pass_result()
	_begin_grid_operation(_last_source_grid_panel)
	var result := _dispatch_action_with_operation_context(action_id)
	_end_grid_operation()
	return result


## UI Button/测试可直接按语义动作与目标请求分发。
func dispatch_action_for_target(
	action_id: StringName,
	target_item: ItemInstanceData,
	source_grid_panel: InventoryGridPanel = null
) -> InventoryInputActionResult:
	if !input_processing_enabled or !_routes_by_action.has(action_id):
		return InventoryInputActionResult.pass_result()
	_begin_grid_operation(source_grid_panel)
	var result := _dispatch_action_with_operation_context(action_id, target_item, true)
	_end_grid_operation()
	return result


func _dispatch_action_with_operation_context(
	action_id: StringName,
	target_override: ItemInstanceData = null,
	has_target_override := false
) -> InventoryInputActionResult:
	var route := _routes_by_action.get(action_id) as InventoryInputActionRoute
	if route == null:
		return InventoryInputActionResult.pass_result()
	var target_item := target_override if has_target_override else _resolve_action_target_item(action_id)
	var context := InventoryInputActionContext.create(
		action_id,
		self,
		_get_operation_inventory_data(),
		target_item,
		_resolve_action_target_cell(),
		_find_held_item_session(),
		inventory_transfer_center
	)
	var observer_tokens: Array[Variant] = []
	for observer in _action_observers:
		observer_tokens.append(observer.before_action(context))
	var result := InventoryInputActionResult.pass_result()
	for processor in route.processors:
		var processor_result := processor.process(context)
		if processor_result == null:
			result = InventoryInputActionResult.rejected(&"inventory_processor_returned_null")
			break
		result = processor_result
		if result.status != InventoryInputActionResult.Status.PASS:
			break
	for index in range(_action_observers.size()):
		_action_observers[index].after_action(context, result, observer_tokens[index])
	return result


func activate_input(source_grid_panel: InventoryGridPanel = null) -> void:
	if !input_processing_enabled or _routes_by_action.is_empty() or !is_inside_tree():
		return
	if is_instance_valid(source_grid_panel):
		_last_source_grid_panel = source_grid_panel
	var services := InventorySceneServices.get_or_create(self)
	if services != null:
		services.get_input_action_router().set_active_controller(self)


func deactivate_input() -> void:
	if !is_inside_tree():
		return
	var services := InventorySceneServices.find_existing(self)
	if services != null:
		services.get_input_action_router().clear_active_controller(self)


func _is_pointer_action_available(source_grid_panel: InventoryGridPanel) -> bool:
	var grid := source_grid_panel if is_instance_valid(source_grid_panel) else inventory_grid_panel
	return is_instance_valid(grid) and grid.is_mouse_in_cells()


func refresh_mouse_pointed_item(source_grid_panel: InventoryGridPanel = null) -> void:
	if !is_pointer_tracking_enabled():
		return
	_begin_grid_operation(source_grid_panel)
	var pointed_item: ItemInstanceData
	var pointed_cell := Vector2i(-1, -1)
	var grid := _get_operation_grid_panel()
	if is_instance_valid(grid) and grid.is_mouse_in_cells():
		pointed_cell = grid.get_mouse_cell()
		pointed_item = _get_mouse_pointed_item_instance()
		_last_source_grid_panel = grid
	_end_grid_operation()
	_last_target_cell = pointed_cell
	if pointed_item == _last_pointed_item_instance:
		return
	_last_pointed_item_instance = pointed_item
	mouse_pointed_item_instance.emit(pointed_item)


func get_mouse_pointed_item_instance() -> ItemInstanceData:
	return _last_pointed_item_instance if is_pointer_tracking_enabled() else null


func _resolve_action_target_item(_action_id: StringName) -> ItemInstanceData:
	var current := _get_mouse_pointed_item_instance()
	return current if current != null else _last_pointed_item_instance


func _resolve_action_target_cell() -> Vector2i:
	var grid := _get_operation_grid_panel()
	if is_instance_valid(grid) and grid.is_mouse_in_cells():
		return grid.get_mouse_cell()
	return _last_target_cell


func _get_mouse_pointed_item_instance() -> ItemInstanceData:
	var grid := _get_operation_grid_panel()
	var operation_inventory := _get_operation_inventory_data()
	if !is_instance_valid(grid) or !is_instance_valid(operation_inventory):
		return null
	var mouse_cell := grid.get_mouse_cell()
	if mouse_cell == Vector2i(-1, -1):
		return null
	return operation_inventory.get_occupy_map().get_item_in_cell(mouse_cell)


func can_process_primary_action(context: InventoryInputActionContext) -> bool:
	return context != null and (
		(context.held_item != null and context.target_cell != Vector2i(-1, -1))
		or context.target_item != null
	)


func try_pick_target(context: InventoryInputActionContext, single_mode: bool) -> bool:
	var item := context.target_item
	if item == null:
		return false
	if single_mode:
		var taken_item := try_take_item_quantity_from_inventory(item, 1)
		if taken_item == null:
			return false
		pick_item_instance(taken_item)
		return true
	var source_cell := context.inventory.get_occupy_map().get_item_center_cell(item)
	if !try_take_item_from_inventory(item):
		return false
	pick_item_instance(item, source_cell)
	return true


func try_lay_held_at_target(context: InventoryInputActionContext, single_mode: bool) -> bool:
	if !has_taking_item() or context.target_cell == Vector2i(-1, -1):
		return false
	return _try_lay_one_at_cell(context.target_cell) if single_mode else _try_lay_whole_at_cell(context.target_cell)


func _try_lay_whole_at_cell(cell: Vector2i) -> bool:
	var session := _get_held_item_session()
	var operation_inventory := _get_operation_inventory_data()
	if !is_instance_valid(session) or !is_instance_valid(operation_inventory):
		return false
	var item := session.get_held_item()
	if operation_inventory.can_place_item_in_cell(get_operation_context(), item, cell):
		if try_place_item_into_inventory(item, cell):
			_clear_taking_item_box()
			return true
	elif operation_inventory.can_merge_item_in_cell(get_operation_context(), item, cell):
		if try_merge_item_in_inventory(item, cell):
			if item.num == 0:
				_clear_taking_item_box()
			return true
	elif operation_inventory.can_replace_item_in_cell(get_operation_context(), item, cell):
		var replaced := try_replace_item_in_inventory(item, cell)
		if replaced != null:
			_clear_taking_item_box()
			pick_item_instance(replaced, cell)
			return true
	_play_invalid_place_feedback()
	return false


func _try_lay_one_at_cell(cell: Vector2i) -> bool:
	var session := _get_held_item_session()
	var operation_inventory := _get_operation_inventory_data()
	if !is_instance_valid(session) or !is_instance_valid(operation_inventory):
		return false
	var item := session.get_held_item()
	var target_item := operation_inventory.get_occupy_map().get_item_in_cell(cell)
	var succeeded := try_place_item_quantity_into_inventory(item, cell, 1) \
		if target_item == null else try_merge_item_quantity_in_inventory(item, cell, 1)
	if succeeded:
		if item.num <= 0 or operation_inventory.has_item_instance(item):
			_clear_taking_item_box()
		return true
	_play_invalid_place_feedback()
	return false


func can_process_quick_transfer_action(context: InventoryInputActionContext) -> bool:
	return context != null and context.held_item == null and context.target_item != null and is_instance_valid(context.transfer_center)


func perform_quick_transfer_action(context: InventoryInputActionContext) -> bool:
	if context.transfer_center.try_transfer_item(
		context.controller.inventory_host, context.target_item,
		1 if context.action_id == InventoryInputActionIds.QUICK_TRANSFER_SINGLE else -1
	):
		return true
	_play_invalid_quick_transfer_feedback(context.target_item)
	return false


func can_process_rotate_action(context: InventoryInputActionContext) -> bool:
	return context != null and (context.held_item != null or context.target_item != null)


func perform_rotate_action(context: InventoryInputActionContext) -> bool:
	if context.held_item != null:
		var session := _find_held_item_session()
		return is_instance_valid(session) and session.try_rotate_held_item()
	if try_rotate_item_in_inventory(context.target_item):
		return true
	_play_invalid_rotate_feedback(context.target_item)
	return false


func has_taking_item() -> bool:
	var session := _find_held_item_session()
	return is_instance_valid(session) and session.has_held_item()


func pick_item_instance(
	item_instance_data: ItemInstanceData,
	source_center_cell: Vector2i = Vector2i(-1, -1)
) -> void:
	var session := _get_held_item_session()
	if is_instance_valid(session):
		session.begin_hold(operation_endpoint, item_instance_data, _get_operation_inventory_data(), source_center_cell, _get_grid_cell_size())
		session.source_controller_ref = weakref(self)


func try_take_item_from_inventory(item: ItemInstanceData) -> bool:
	var operation_inventory := _get_operation_inventory_data()
	return is_instance_valid(operation_inventory) and item != null and operation_inventory.try_take_item(get_operation_context(), item)


func try_take_item_quantity_from_inventory(item: ItemInstanceData, quantity: int) -> ItemInstanceData:
	var operation_inventory := _get_operation_inventory_data()
	if !is_instance_valid(operation_inventory) or item == null:
		return null
	return operation_inventory.try_take_item_quantity(get_operation_context(), item, quantity)


func try_place_item_into_inventory(item: ItemInstanceData, cell: Vector2i) -> bool:
	var operation_inventory := _get_operation_inventory_data()
	return is_instance_valid(operation_inventory) and item != null and operation_inventory.try_place_item_in_cell(get_operation_context(), item, cell)


func try_place_item_quantity_into_inventory(
	item: ItemInstanceData, cell: Vector2i, quantity: int
) -> bool:
	var operation_inventory := _get_operation_inventory_data()
	return is_instance_valid(operation_inventory) and item != null \
		and operation_inventory.try_place_item_quantity_in_cell(get_operation_context(), item, cell, quantity)


func try_rotate_item_in_inventory(item: ItemInstanceData) -> bool:
	var operation_inventory := _get_operation_inventory_data()
	return is_instance_valid(operation_inventory) and item != null and operation_inventory.try_rotate_item_in_inventory_best_effort(get_operation_context(), item)


func try_merge_item_in_inventory(item: ItemInstanceData, cell: Vector2i) -> bool:
	var operation_inventory := _get_operation_inventory_data()
	return is_instance_valid(operation_inventory) and item != null and operation_inventory.try_merge_item_in_cell(get_operation_context(), item, cell)


func try_merge_item_quantity_in_inventory(
	item: ItemInstanceData, cell: Vector2i, quantity: int
) -> bool:
	var operation_inventory := _get_operation_inventory_data()
	return is_instance_valid(operation_inventory) and item != null \
		and operation_inventory.try_merge_item_quantity_in_cell(get_operation_context(), item, cell, quantity)


func try_replace_item_in_inventory(item: ItemInstanceData, cell: Vector2i) -> ItemInstanceData:
	var operation_inventory := _get_operation_inventory_data()
	if !is_instance_valid(operation_inventory) or item == null:
		return null
	return operation_inventory.try_replace_item_in_cell(get_operation_context(), item, cell)


func try_add_item_with_merge(item: ItemInstanceData) -> bool:
	var operation_inventory := _get_operation_inventory_data()
	return is_instance_valid(operation_inventory) and item != null and operation_inventory.try_add_item_with_merge(get_operation_context(), item)


func try_add_item_quantity_with_merge(item: ItemInstanceData, quantity: int) -> bool:
	var operation_inventory := _get_operation_inventory_data()
	return is_instance_valid(operation_inventory) and item != null \
		and operation_inventory.try_add_item_quantity_with_merge(get_operation_context(), item, quantity)


func try_add_item_without_merge(item: ItemInstanceData) -> bool:
	var operation_inventory := _get_operation_inventory_data()
	return is_instance_valid(operation_inventory) and item != null and operation_inventory.try_add_item_without_merge(get_operation_context(), item)


func _clear_taking_item_box() -> void:
	var session := _find_held_item_session()
	if is_instance_valid(session):
		session.clear_hold()


func _play_invalid_place_feedback() -> void:
	operation_feedback_requested.emit(null)

func _play_invalid_rotate_feedback(item: ItemInstanceData) -> void:
	operation_feedback_requested.emit(item)

func _play_invalid_quick_transfer_feedback(item: ItemInstanceData) -> void:
	_play_invalid_rotate_feedback(item)


func _get_grid_cell_size() -> Vector2:
	var grid := _get_operation_grid_panel()
	return grid.cell_size if is_instance_valid(grid) else Vector2.ZERO


func _begin_grid_operation(source_grid_panel: InventoryGridPanel) -> void:
	if is_instance_valid(source_grid_panel):
		_operation_grid_panel = source_grid_panel
		_operation_inventory_data = source_grid_panel.inventory_data
		return
	if is_instance_valid(_last_source_grid_panel):
		_operation_grid_panel = _last_source_grid_panel
		_operation_inventory_data = _last_source_grid_panel.inventory_data
		return
	_operation_grid_panel = inventory_grid_panel
	_operation_inventory_data = inventory_data


func _end_grid_operation() -> void:
	_operation_grid_panel = null
	_operation_inventory_data = null


func _get_operation_inventory_data() -> InventoryData:
	return _operation_inventory_data if is_instance_valid(_operation_inventory_data) else inventory_data


func _get_operation_grid_panel() -> InventoryGridPanel:
	return _operation_grid_panel if is_instance_valid(_operation_grid_panel) else inventory_grid_panel


func uses_automatic_placement() -> bool:
	return false

func get_operation_context() -> InventoryOperationContext:
	return InventoryOperationContext.for_endpoint(operation_endpoint)
