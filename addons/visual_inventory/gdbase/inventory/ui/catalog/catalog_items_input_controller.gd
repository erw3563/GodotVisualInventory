@tool
class_name CatalogItemsInputController
extends InventoryItemsInputController
## 目录布局只解析聚合组；物理输入与动作分发复用基类。


@export var catalog_panel: ItemCatalogPanel


func _ready() -> void:
	super._ready()
	if is_instance_valid(catalog_panel):
		catalog_panel.bind_items_input_controller(self)


func _is_pointer_action_available(_source_grid_panel: InventoryGridPanel) -> bool:
	return is_instance_valid(catalog_panel) and catalog_panel.is_mouse_in_panel()


func refresh_mouse_pointed_item(_source_grid_panel: InventoryGridPanel = null) -> void:
	if !is_pointer_tracking_enabled():
		return
	var pointed_item := _get_mouse_pointed_item_instance()
	_last_target_cell = Vector2i(-1, -1)
	if pointed_item == _last_pointed_item_instance:
		return
	_last_pointed_item_instance = pointed_item
	mouse_pointed_item_instance.emit(pointed_item)


func _get_mouse_pointed_item_instance() -> ItemInstanceData:
	var group = get_action_target_group()
	return group.get_representative() if group != null else null


func get_action_target_group():
	return catalog_panel.get_item_group_under_mouse() if is_instance_valid(catalog_panel) else null


func _resolve_action_target_cell() -> Vector2i:
	return Vector2i(-1, -1)


func _get_grid_cell_size() -> Vector2:
	return catalog_panel.get_catalog_cell_size() if is_instance_valid(catalog_panel) else Vector2.ZERO


func can_process_primary_action(context: InventoryInputActionContext) -> bool:
	return context != null and is_instance_valid(inventory_data) and (
		context.held_item != null or context.target_item != null
	)


func try_pick_target(_context: InventoryInputActionContext, single_mode: bool) -> bool:
	return try_pick_group(get_action_target_group(), single_mode)


func try_lay_held_at_target(_context: InventoryInputActionContext, single_mode: bool) -> bool:
	return try_lay_held_item(single_mode)


func try_pick_group(group, single_mode: bool) -> bool:
	if group == null:
		return false
	return _pick_one_from_group(group) if single_mode else _pick_group_stacks(group)


func _pick_group_stacks(group) -> bool:
	if !is_instance_valid(inventory_data):
		return false
	var sorted_instances: Array = group.collect_valid_instances_sorted_by_num_desc()
	if sorted_instances.is_empty():
		return false
	var held: ItemInstanceData = sorted_instances[0]
	if !inventory_data.can_take_item(get_operation_context(), held):
		return false
	var source_cell := inventory_data.get_occupy_map().get_item_center_cell(held)
	if !try_take_item_from_inventory(held):
		return false
	for rest in sorted_instances.slice(1):
		if held.is_full():
			break
		if !is_instance_valid(rest) or rest.get_item_num() <= 0 or !inventory_data.can_take_item(get_operation_context(), rest):
			continue
		_merge_rest_instance_into_held(held, rest)
	pick_item_instance(held, source_cell)
	return true


func _merge_rest_instance_into_held(held: ItemInstanceData, rest: ItemInstanceData) -> void:
	var remain_space := held.get_remain_space_num()
	if remain_space <= 0:
		return
	if rest.get_item_num() <= remain_space:
		if !try_take_item_from_inventory(rest):
			return
		if !held.try_merge_item(rest):
			try_add_item_without_merge(rest)
		return
	var split_item := inventory_data.try_take_item_quantity(get_operation_context(), rest, remain_space)
	if split_item != null and !held.try_merge_item(split_item):
		inventory_data.try_add_item_with_merge(get_operation_context(), split_item)


func _pick_one_from_group(group) -> bool:
	if !is_instance_valid(inventory_data):
		return false
	var target: ItemInstanceData = group.get_smallest_instance()
	if target == null:
		return false
	var source_cell := inventory_data.get_occupy_map().get_item_center_cell(target)
	var taken := inventory_data.try_take_item_quantity(get_operation_context(), target, 1)
	if taken == null:
		return false
	pick_item_instance(taken, source_cell if taken == target else Vector2i(-1, -1))
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


func _resolve_action_target_item(action_id: StringName) -> ItemInstanceData:
	var group = get_action_target_group()
	if group == null:
		return super._resolve_action_target_item(action_id)
	if action_id in [InventoryInputActionIds.PRIMARY_SINGLE, InventoryInputActionIds.QUICK_TRANSFER_SINGLE]:
		return group.get_smallest_instance()
	if action_id in [InventoryInputActionIds.PRIMARY, InventoryInputActionIds.QUICK_TRANSFER]:
		return group.get_largest_instance()
	return group.get_representative()


func uses_automatic_placement() -> bool:
	return true
