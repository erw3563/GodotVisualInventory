@tool
class_name FreeItemsInputController
extends InventoryItemsInputController
## 自由格布局只解析目标；物理输入与动作分发复用基类。


@export var free_panel: FreeItemsPanel

## GUI 事件携带面板局部坐标；分发期间使用该快照，不重读系统光标。
var _pointer_event: InputEventMouseButton


func _ready() -> void:
	super._ready()
	if is_instance_valid(free_panel):
		free_panel.bind_items_input_controller(self)


func handle_pointer_input(event: InputEvent, source_grid_panel: InventoryGridPanel = null) -> bool:
	var previous_event := _pointer_event
	_pointer_event = event as InputEventMouseButton
	var handled := super.handle_pointer_input(event, source_grid_panel)
	_pointer_event = previous_event
	return handled


func _is_pointer_action_available(_source_grid_panel: InventoryGridPanel) -> bool:
	if !is_instance_valid(free_panel) or !free_panel.is_visible_in_tree():
		return false
	if _pointer_event != null:
		return free_panel._has_point(_pointer_event.position)
	return free_panel.is_mouse_in_panel()


func refresh_mouse_pointed_item(_source_grid_panel: InventoryGridPanel = null) -> void:
	if !is_pointer_tracking_enabled():
		return
	var pointed_item := _get_mouse_pointed_item_instance()
	_last_target_cell = Vector2i(-1, -1)
	if pointed_item == _last_pointed_item_instance:
		return
	_last_pointed_item_instance = pointed_item
	mouse_pointed_item_instance.emit(pointed_item)


## 动态布局只使用当前命中，不回退到已转走或移出的悬停实例。
func _resolve_action_target_item(_action_id: StringName) -> ItemInstanceData:
	return _get_mouse_pointed_item_instance()


func _get_mouse_pointed_item_instance() -> ItemInstanceData:
	if !_is_pointer_action_available(null):
		return null
	if _pointer_event != null:
		return free_panel.get_item_at_position(free_panel.get_global_transform() * _pointer_event.position)
	return free_panel.get_item_under_mouse()


func _resolve_action_target_cell() -> Vector2i:
	return Vector2i(-1, -1)


func _get_grid_cell_size() -> Vector2:
	return free_panel.get_free_cell_size() if is_instance_valid(free_panel) else Vector2.ZERO


func can_process_primary_action(context: InventoryInputActionContext) -> bool:
	return context != null and is_instance_valid(inventory_data) and (
		context.held_item != null or context.target_item != null
	)


func try_pick_target(context: InventoryInputActionContext, single_mode: bool) -> bool:
	return try_pick_instance(context.target_item, single_mode)


func try_lay_held_at_target(_context: InventoryInputActionContext, single_mode: bool) -> bool:
	return try_lay_held_item(single_mode)


func try_pick_instance(item: ItemInstanceData, single_mode: bool) -> bool:
	if !is_instance_valid(inventory_data) or item == null:
		return false
	if single_mode:
		var taken := inventory_data.try_take_item_quantity(get_operation_context(), item, 1)
		if taken == null:
			return false
		pick_item_instance(taken)
		return true
	var source_cell := inventory_data.get_occupy_map().get_item_center_cell(item)
	if !try_take_item_from_inventory(item):
		return false
	pick_item_instance(item, source_cell)
	return true


func try_lay_held_item(single_mode: bool) -> bool:
	if !has_taking_item() or !is_instance_valid(inventory_data):
		return false
	var session := _get_held_item_session()
	if !is_instance_valid(session):
		return false
	var item := session.get_held_item()
	var succeeded := try_add_item_quantity_with_merge(item, 1) \
		if single_mode else try_add_item_with_merge(item)
	if !succeeded:
		_play_invalid_place_feedback()
		return false
	if item.get_item_num() <= 0 or inventory_data.has_item_instance(item):
		_clear_taking_item_box()
	return true


func can_process_rotate_action(context: InventoryInputActionContext) -> bool:
	return context != null and context.held_item != null


func perform_quick_transfer_action(context: InventoryInputActionContext) -> bool:
	if context.transfer_center.try_transfer_item(
		context.controller.inventory_host, context.target_item,
		1 if context.action_id == InventoryInputActionIds.QUICK_TRANSFER_SINGLE else -1
	):
		return true
	_play_invalid_quick_transfer_feedback(context.target_item)
	return false


func uses_automatic_placement() -> bool:
	return true
