@abstract
class_name InventoryItemsPanel
extends Control
## 背包物品面板基类 InventoryItemsPanel。
## 仅负责根据 InventoryData 的信号刷新物品显示，不执行放置、取出、旋转等数据操作。

#region 导出属性与变量
## 背包数据
@export var inventory_data:InventoryData:
	set(value):
		_try_disconnect_inventory_data_signal()
		inventory_data = value
		if !is_node_ready():
			await ready
		_apply_inventory_data_binding()
var item_data_to_item_boxes:Dictionary[ItemInstanceData,InventoryItemBox]
#endregion

#region 抽象接口
@abstract func _get_pos_by_cell(cell:Vector2i)->Vector2 ## 依照格子坐标返回物品格在面板中的局部位置
@abstract func _get_item_texture_size() -> Vector2 ## 返回物品框中物品贴图的大小
@abstract func _get_item_box_size() -> Vector2 ## 返回物品框的大小
#endregion

#region 生命周期
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("InventoryItemsPanel")
	_try_update_all_item_boxes()
#endregion

#region InventoryData 绑定与刷新
## 设置背包数据
func set_inventory_data(inventory_data_:InventoryData):
	inventory_data = inventory_data_

## 连接信号并刷新全部物品格显示。
func _apply_inventory_data_binding() -> void:
	_try_connect_inventory_data_signal()
	_try_update_all_item_boxes()

## 强制刷新全部物品格显示（inventory_data 引用未变时也可调用）。
func refresh_display() -> void:
	_try_update_all_item_boxes()

## 全面更新背包物品
func _try_update_all_item_boxes() -> void:
	## 清除当前所有的物品实例以防止旧实例残余
	clear_all_item_box()
	if inventory_data:
		_create_and_place_all_item_boxes()
#endregion

#region 库存数据信号
func _try_connect_inventory_data_signal():
	if !inventory_data:
		return
	_set_inventory_data_signals(true)

func _try_disconnect_inventory_data_signal():
	if !inventory_data:
		return
	_set_inventory_data_signals(false)

## 统一处理背包数据相关信号的连接与断开。
func _set_inventory_data_signals(is_connect: bool) -> void:
	_set_signal_connection(inventory_data.item_added, _try_create_and_place_item_box_on_inventory_item_added, is_connect)
	_set_signal_connection(inventory_data.item_removed, _try_erase_item_box_on_inventory_item_removed, is_connect)
	_set_signal_connection(inventory_data.item_position_changed, _try_refresh_item_box_position_on_item_position_changed, is_connect)
	_set_signal_connection(inventory_data.item_corrected, _try_refresh_item_box_on_item_corrected, is_connect)
	_set_signal_connection(inventory_data.item_rotated, _try_refresh_item_box_on_item_rotated, is_connect)
	_set_signal_connection(inventory_data.item_reshaped, _try_refresh_item_box_on_item_reshaped, is_connect)
	_set_signal_connection(inventory_data.sorted, _try_update_all_item_boxes, is_connect)
	_set_signal_connection(inventory_data.inventory_cleared, _try_update_all_item_boxes, is_connect)
	_set_signal_connection(inventory_data.occupy_map_changed, _try_update_all_item_boxes, is_connect)
	_set_signal_connection(inventory_data.item_cannot_be_handled, _on_inventory_item_cannot_be_handled, is_connect)

## 根据目标状态设置单条信号连接，避免重复代码和重复连接。
func _set_signal_connection(target_signal: Signal, target_callable: Callable, is_connect: bool) -> void:
	if is_connect:
		if !target_signal.is_connected(target_callable):
			target_signal.connect(target_callable)
	else:
		if target_signal.is_connected(target_callable):
			target_signal.disconnect(target_callable)
#endregion

#region 物品格显示更新
## 根据 inventory_data 中的 item_instance_data 创建所有的背包物品格子，也是初始化背包物品方法。
func _create_and_place_all_item_boxes():
	for item_instance_data in inventory_data.get_item_instances():
		if _can_display_item_instance(item_instance_data):
			_try_create_and_place_item_box_on_inventory_item_added(item_instance_data)

## 根据 item_instance_data 创建背包物品格子。该方法会且仅会被 inventory_data 中的 item_added 信号调用。
func _try_create_and_place_item_box_on_inventory_item_added(item_instance_data:ItemInstanceData):
	if !_can_display_item_instance(item_instance_data):
		return
	if _has_item_box_from_item_instance_data(item_instance_data): # 判断当前数据是否已经有 item_box
		return
	var inventory_item_box = _create_item_box(item_instance_data)
	add_child(inventory_item_box)
	inventory_item_box.set_deferred("position", _calculate_item_box_position(item_instance_data))

## 根据 item_instance_data 移除背包物品格子。该方法会且仅会被 inventory_data 中的 item_removed 信号调用。
func _try_erase_item_box_on_inventory_item_removed(item_instance_data:ItemInstanceData):
	if !item_data_to_item_boxes.has(item_instance_data):
		return
	var item_box := item_data_to_item_boxes[item_instance_data]
	item_box.free()
	item_data_to_item_boxes.erase(item_instance_data)

## 背包数据报告该物品无法处理时，立即移除其显示。
func _on_inventory_item_cannot_be_handled(item_instance_data: ItemInstanceData) -> void:
	_try_erase_item_box_on_inventory_item_removed(item_instance_data)

## 物品占位校正成功时刷新对应物品格的显示（此前可能因错误占位未显示）。
func _try_refresh_item_box_on_item_corrected(
	item_instance_data: ItemInstanceData,
	_previous_cell: Vector2i
) -> void:
	_try_refresh_item_box_position_on_item_position_changed(item_instance_data, _previous_cell)

## 物品位置变化时刷新对应物品格的显示位置。
func _try_refresh_item_box_position_on_item_position_changed(
	item_instance_data: ItemInstanceData,
	_previous_cell: Vector2i
) -> void:
	if !_can_display_item_instance(item_instance_data):
		_try_erase_item_box_on_inventory_item_removed(item_instance_data)
		return
	if !_has_item_box_from_item_instance_data(item_instance_data):
		_try_create_and_place_item_box_on_inventory_item_added(item_instance_data)
		return
	_refresh_item_box_position(item_instance_data)

## 物品旋转时刷新对应物品格的显示位置。
func _try_refresh_item_box_on_item_rotated(item_instance_data: ItemInstanceData) -> void:
	if !_can_display_item_instance(item_instance_data):
		_try_erase_item_box_on_inventory_item_removed(item_instance_data)
		return
	if !_has_item_box_from_item_instance_data(item_instance_data):
		_try_create_and_place_item_box_on_inventory_item_added(item_instance_data)
		return
	_refresh_item_box_position(item_instance_data)

## 物品轮廓变形时刷新对应物品格的尺寸与位置。
func _try_refresh_item_box_on_item_reshaped(item_instance_data: ItemInstanceData) -> void:
	if !_can_display_item_instance(item_instance_data):
		_try_erase_item_box_on_inventory_item_removed(item_instance_data)
		return
	if !_has_item_box_from_item_instance_data(item_instance_data):
		_try_create_and_place_item_box_on_inventory_item_added(item_instance_data)
		return
	var inventory_item_box := item_data_to_item_boxes[item_instance_data]
	inventory_item_box.refresh_display()
	_refresh_item_box_position(item_instance_data)

## 刷新单个物品格子的显示位置。
func _refresh_item_box_position(item_instance_data: ItemInstanceData) -> void:
	if !item_data_to_item_boxes.has(item_instance_data):
		return
	var inventory_item_box := item_data_to_item_boxes[item_instance_data]
	inventory_item_box.position = _calculate_item_box_position(item_instance_data)

## 计算物品格在面板中的显示位置：盒左上角对齐「锚点格 + 旋转包围盒 min」格，
## 使盒子覆盖物品实际占格的包围盒（形状含负坐标或 (0,0) 为空洞时同样正确）。
func _calculate_item_box_position(item_instance_data: ItemInstanceData) -> Vector2:
	var center_cell := _get_item_display_center_cell(item_instance_data)
	var rotated_rect := item_instance_data.get_rotated_shape_rect()
	return _get_pos_by_cell(center_cell + rotated_rect.position)

## 获取物品实例在当前占位图中的中心格。
func _get_item_display_center_cell(item_instance_data: ItemInstanceData) -> Vector2i:
	var inventory_occupy_map := inventory_data.get_occupy_map()
	if inventory_occupy_map == null:
		return Vector2i(-1, -1)
	return inventory_occupy_map.get_item_center_cell(item_instance_data)
#endregion

#region 物品格管理
## 创建背包内的物品格子
func _create_item_box(item_instance_data:ItemInstanceData)->InventoryItemBox:
	var inventory_items_box = InventoryItemBox.new()
	inventory_items_box.init_cell(item_instance_data, _get_item_texture_size(), _get_item_box_size())
	inventory_items_box.icon_view.set_sync_callback(_sync_item_view)
	item_data_to_item_boxes[item_instance_data] = inventory_items_box
	return inventory_items_box

## 清除背包中所有物品
func clear_all_item_box():
	for inventory_item_box in _get_all_item_boxes():
		inventory_item_box.queue_free()
	item_data_to_item_boxes.clear()
#endregion

#region 判断
## 判断物品实例是否应在当前面板中显示（能定位锚点格且确在占位图中占格即可；
## 锚点格本身可能是空洞——环形等形状的 (0,0) 不属于形状，不能以它验证归属）。
func _can_display_item_instance(item_instance_data: ItemInstanceData) -> bool:
	if item_instance_data == null:
		return false
	if !inventory_data:
		return false
	var inventory_occupy_map := inventory_data.get_occupy_map()
	if !inventory_occupy_map:
		return false
	var center_cell := inventory_occupy_map.get_item_center_cell(item_instance_data)
	if center_cell == Vector2i(-1, -1):
		return false
	return inventory_occupy_map.has_item_instance_in_occupancy(item_instance_data)

func _has_item_box_from_item_instance_data(item_instance_data:ItemInstanceData)->bool:
	return item_data_to_item_boxes.has(item_instance_data)

func _has_item_box(inventory_item_box:InventoryItemBox):
	return item_data_to_item_boxes.find_key(inventory_item_box)
#endregion

#region 获取
## 获取背包数据
func get_inventory_data()->InventoryData:
	return inventory_data

## 获取指定格子中的 InventoryItemBox。
func get_item_box_at_cell(cell:Vector2i) -> InventoryItemBox:
	return _get_item_box_at_cell(cell)

## 获取所有 InventoryItemBox
func _get_all_item_boxes() -> Array[InventoryItemBox]:
	return item_data_to_item_boxes.values()

## 获取在册物品的屏幕矩形；不在册（未显示或已移除）时返回 Rect2()。
func get_item_box_screen_rect(item_instance_data:ItemInstanceData)->Rect2:
	if !item_data_to_item_boxes.has(item_instance_data):
		return Rect2()
	return item_data_to_item_boxes[item_instance_data].get_global_rect()

## 获取与物品同种数据任意一堆的屏幕矩形（转移合并被吸收时的落点回退）；无时返回 Rect2()。
func get_same_item_box_screen_rect(item_instance_data:ItemInstanceData)->Rect2:
	if item_instance_data==null:
		return Rect2()
	for inventory_item_box in item_data_to_item_boxes.values():
		var box_item: ItemInstanceData = inventory_item_box.get_item_instance_data()
		if box_item!=null and box_item.item_data==item_instance_data.item_data:
			return inventory_item_box.get_global_rect()
	return Rect2()

## 延迟物品图标的显示（动画组件调用：幽灵飞行期间目标格图标暂隐，抵达后淡入显现）。
## 仅对物品的自有格子生效；合并被吸收（不在册）等场景返回 false 不延迟。
func delay_item_icon_display(item_instance_data:ItemInstanceData, duration:float, fade_in_time:float=0.12)->bool:
	if !item_data_to_item_boxes.has(item_instance_data):
		return false
	item_data_to_item_boxes[item_instance_data].delay_icon_display(duration, fade_in_time)
	return true

## 动画持有自有格子的图标隐藏；合并被吸收时不影响幸存堆。
func acquire_item_icon_display_hold(item_instance_data: ItemInstanceData) -> Callable:
	if not item_data_to_item_boxes.has(item_instance_data):
		return Callable()
	return item_data_to_item_boxes[item_instance_data].acquire_icon_display_hold()


## 根据背包物品数据获取拥有其的背包物品格子
func _get_item_box_from_item_instance_data(item_instance_data:ItemInstanceData)->InventoryItemBox:
	return item_data_to_item_boxes[item_instance_data]

## 根据坐标获取 InventoryItemBox
func _get_item_box_at_cell(cell:Vector2i) -> InventoryItemBox:
	var res_box:InventoryItemBox
	var inventory_occupy_map := inventory_data.get_occupy_map()
	for item_instance_data in item_data_to_item_boxes.keys():
		if inventory_occupy_map == null:
			continue
		var item_cells: Array[Vector2i] = inventory_occupy_map.get_cells_of_occupant(item_instance_data)
		if item_cells.has(cell):
			res_box = _get_item_box_from_item_instance_data(item_instance_data)
			break
	return res_box
#endregion


var _view_provider: InventoryItemViewProvider

func set_view_provider(provider: InventoryItemViewProvider) -> void:
	_view_provider = provider
	for cell in item_data_to_item_boxes.values():
		if is_instance_valid(cell) and is_instance_valid(cell.icon_view):
			cell.icon_view.set_sync_callback(_sync_item_view)

func _sync_item_view(item: ItemInstanceData, view: ItemIconView) -> void:
	if _view_provider != null:
		_view_provider.sync_view(item, view)

func get_item_views(item: ItemInstanceData) -> Array[ItemIconView]:
	var cell = item_data_to_item_boxes.get(item)
	if is_instance_valid(cell) and not cell.is_queued_for_deletion() and cell.icon_view.get_bound_item() == item:
		return [cell.icon_view]
	return []
