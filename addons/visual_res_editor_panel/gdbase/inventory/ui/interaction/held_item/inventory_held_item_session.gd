@tool
class_name InventoryHeldItemSession
extends Node
## 场景级手持物品会话：持有状态、挂载视图、发出变化通知、放回来源背包。
## 由 InventorySceneServices 统一创建并持有。

signal held_item_changed

## 当前手持物品数据。
var held_item_instance_data: ItemInstanceData
## 手持物品来源背包。
var source_endpoint: InventoryOperationEndpoint
var source_controller_ref: WeakRef
var source_inventory_data: InventoryData
## 手持物品拿取前的来源中心格。
var held_item_source_center_cell: Vector2i = Vector2i(-1, -1)
## 手持物品视图。
var held_item_view: InventoryHeldItemView
## 可选挂载父节点覆盖（编辑器等无 HUD 层时使用）。
var preferred_view_parent: Node
## 查询依赖与显示父节点分离，由场景服务显式注入。
var view_provider: InventoryItemViewProvider
## 记录最近一次手持旋转所处的帧，避免同帧重复旋转。
var _last_rotate_process_frame: int = -1
var _revision := 0

## 捕获可逆发布所需的运行事实，视图由调用方保留至事务终结。
func capture_restore_state() -> InventoryHeldItemRestoreState:
	var state := InventoryHeldItemRestoreState.new()
	state.item = held_item_instance_data
	state.source_inventory = source_inventory_data
	state.endpoint = source_endpoint
	state.controller_ref = source_controller_ref
	state.source_cell = held_item_source_center_cell
	state.view = held_item_view
	state.view_visible = held_item_view.visible if is_instance_valid(held_item_view) else false
	state.rotate_frame = _last_rotate_process_frame
	state.revision = _revision
	return state

## 恢复事务静默安装完整会话状态；提交完成后统一发出 held_item_changed。
func install_restore_state(state: InventoryHeldItemRestoreState) -> bool:
	if state == null or not state.validate_view():
		return false
	if is_instance_valid(held_item_view) and held_item_view != state.view:
		held_item_view.hide()
	held_item_instance_data = state.item
	source_inventory_data = state.source_inventory
	source_endpoint = state.endpoint
	source_controller_ref = state.controller_ref
	held_item_source_center_cell = state.source_cell
	held_item_view = state.view
	_last_rotate_process_frame = state.rotate_frame
	_revision = state.revision
	if is_instance_valid(held_item_view):
		held_item_view.visible = state.view_visible
	return true


## 开始手持指定物品并更新视图（来源为拼图背包）。
func begin_hold(
	endpoint: InventoryOperationEndpoint,
	item_instance_data: ItemInstanceData,
	source_inventory: InventoryData,
	source_center_cell: Vector2i,
	item_cell_size: Vector2
) -> void:
	if !is_instance_valid(item_instance_data):
		return
	_begin_hold_common(item_instance_data, item_cell_size)
	source_endpoint = endpoint
	source_inventory_data = source_inventory
	held_item_source_center_cell = source_center_cell
	_revision += 1
	held_item_changed.emit()


## 设置手持物品与视图的公共逻辑。
func _begin_hold_common(item_instance_data: ItemInstanceData, item_cell_size: Vector2) -> void:
	_ensure_held_item_view()
	source_controller_ref = null
	held_item_instance_data = item_instance_data
	_last_rotate_process_frame = -1
	if is_instance_valid(held_item_view):
		held_item_view.view_provider = view_provider
		held_item_view.set_display_item(item_instance_data, item_cell_size, item_cell_size)


## 清除手持状态与视图。
func clear_hold() -> void:
	held_item_instance_data = null
	source_inventory_data = null
	source_endpoint = null
	source_controller_ref = null
	held_item_source_center_cell = Vector2i(-1, -1)
	_last_rotate_process_frame = -1
	if is_instance_valid(held_item_view):
		held_item_view.clear_held_item()
	_revision += 1
	held_item_changed.emit()


## 当前是否存在手持物品。
func has_held_item() -> bool:
	return is_instance_valid(held_item_instance_data)


## 获取当前手持物品。
func get_held_item() -> ItemInstanceData:
	return held_item_instance_data


## 获取手持物品来源中心格。
func get_held_item_source_center_cell() -> Vector2i:
	return held_item_source_center_cell


## 判断手持物品是否来自指定背包。
func is_holding_from(target_inventory_data: InventoryData) -> bool:
	if !has_held_item():
		return false
	return source_inventory_data == target_inventory_data


## 尝试旋转手持物品，并保证同一帧只旋转一次。
func try_rotate_held_item() -> bool:
	if !has_held_item():
		return false
	var current_process_frame := Engine.get_process_frames()
	if current_process_frame == _last_rotate_process_frame:
		return false
	_last_rotate_process_frame = current_process_frame
	held_item_instance_data.dir = ShapeTransform.rotate_dir_clockwise(held_item_instance_data.dir, 1)
	_revision += 1
	held_item_changed.emit()
	return true


## 将手持物品放回来源背包（优先原格子），并清除手持显示。
func try_restore_to_source_inventory() -> bool:
	if !has_held_item():
		return false
	if !is_instance_valid(held_item_instance_data):
		clear_hold()
		return false
	if !is_instance_valid(source_inventory_data):
		return false

	if source_endpoint == null or source_endpoint.validate(source_inventory_data) != &"":
		return false
	var operation_context := InventoryOperationContext.for_endpoint(source_endpoint)
	var source_controller := source_controller_ref.get_ref() as InventoryItemsInputController if source_controller_ref != null else null
	if source_controller == null or source_controller.get_operation_context().source_endpoint != source_endpoint:
		return false
	var restored := false
	var original_cell := held_item_source_center_cell
	if original_cell != Vector2i(-1, -1) and source_inventory_data.can_place_item_in_cell(operation_context, held_item_instance_data, original_cell):
		restored = source_controller.try_place_item_into_inventory(held_item_instance_data, original_cell)
	if not restored:
		restored = source_controller.try_add_item_with_merge(held_item_instance_data)
	if not restored:
		restored = source_controller.try_add_item_without_merge(held_item_instance_data)
	if restored:
		clear_hold()
	return restored



## 确保手持视图已创建并挂载到可见树中。
func _ensure_held_item_view() -> void:
	var parent_node := _get_held_item_view_parent()
	if !is_instance_valid(parent_node):
		return
	if is_instance_valid(held_item_view):
		_mount_held_item_view(parent_node)
		return
	held_item_view = InventoryHeldItemView.new()
	_mount_held_item_view(parent_node)


## 获取手持物品视图的挂载父节点。
func _get_held_item_view_parent() -> Node:
	if is_instance_valid(preferred_view_parent):
		return preferred_view_parent
	if is_inside_tree():
		var current_scene := get_tree().current_scene
		if is_instance_valid(current_scene):
			return current_scene
	return self


## 将手持物品视图挂到指定父节点。
func _mount_held_item_view(parent_node: Node) -> void:
	if !is_instance_valid(held_item_view) or !is_instance_valid(parent_node):
		return
	if held_item_view.get_parent() == parent_node:
		return
	if held_item_view.get_parent() != null:
		held_item_view.get_parent().remove_child(held_item_view)
	parent_node.add_child(held_item_view)
