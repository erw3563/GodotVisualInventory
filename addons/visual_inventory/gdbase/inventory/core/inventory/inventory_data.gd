@tool
class_name InventoryData
extends Resource
## InventoryData是背包数据文件。
## 背包成员权威来源为 occupy_map 的 occupancy；item_instances 仅为派生缓存。

#region 信号
## 占位图合法区域大小变化时触发。
signal occupy_map_changed
## 背包整理完成时触发（整理流程内仅通过 item_position_changed 等细粒度信号通知变化，结束时发出本信号）。
signal sorted
## 物品添加时触发
signal item_added(item:ItemInstanceData)
## 物品移除时触发
signal item_removed(item:ItemInstanceData)
## 物品在背包内的中心格位置发生变化时触发（previous_cell 为变化前的中心格坐标）。
signal item_position_changed(item: ItemInstanceData, previous_cell: Vector2i)
## 物品在背包内旋转时触发。
signal item_rotated(item: ItemInstanceData)
## 物品在背包内轮廓变形时触发。
signal item_reshaped(item: ItemInstanceData)
## 占位图无法为物品找到合法位置时触发（重叠、越界且背包无可用空位等）。
signal item_cannot_be_handled(item: ItemInstanceData)
## 物品占位校正成功时触发（重叠或越界坐标已重新注册，previous_cell 为校正前的中心格坐标）。
signal item_corrected(item: ItemInstanceData, previous_cell: Vector2i)
## 物品移除时触发
signal item_removed_in_cell(item: ItemInstanceData, removed_center_cell: Vector2i)
## 全部物品移除时触发
signal inventory_cleared
## 一份完整 Plan 成功提交并更新修订号后触发。
signal operation_committed(result: InventoryOperationResult)
#endregion

#region 数据字段
## 派生缓存：成员以 occupy_map occupancy 为准，勿当作独立权威写入。
@export var item_instances: Array[ItemInstanceData]
## 背包占位图
@export var occupy_map: InventoryOccupyMap:
	set(value):
		_disconnect_occupy_map_signals()
		occupy_map = value
		_connect_occupy_map_signals()
## 正常玩法提交修订号；Planner 用它拒绝陈旧方案。
var revision: int = 0
#endregion

## 默认占位图区域尺寸；显式 init_occupy_map 或序列化的 occupy_map 均可整体覆盖。
const DEFAULT_OCCUPY_MAP_SIZE := Vector2i(3, 3)

func _init() -> void:
	occupy_map = ShapeInventoryOccupyMap.new()
	occupy_map.init_region_by_size(DEFAULT_OCCUPY_MAP_SIZE)

#region 初始化与信号绑定

## 连接当前占位图资源上的变化信号。
func _connect_occupy_map_signals() -> void:
	if !occupy_map:
		return
	_set_occupy_map_signal_connection(occupy_map.map_changed, occupy_map_changed.emit, true)
	_set_occupy_map_signal_connection(occupy_map.item_instance_added, _on_occupy_map_item_instance_added, true)
	_set_occupy_map_signal_connection(occupy_map.item_instance_removed, _on_occupy_map_item_instance_removed, true)
	_set_occupy_map_signal_connection(occupy_map.item_instance_position_changed, _on_occupy_map_item_instance_position_changed, true)
	_set_occupy_map_signal_connection(occupy_map.item_instance_rotated, _on_occupy_map_item_instance_rotated, true)
	_set_occupy_map_signal_connection(occupy_map.item_instance_reshaped, _on_occupy_map_item_instance_reshaped, true)
	_set_occupy_map_signal_connection(occupy_map.item_instance_cannot_be_handled, _on_occupy_map_item_instance_cannot_be_handled, true)
	_set_occupy_map_signal_connection(occupy_map.item_instance_corrected, _on_occupy_map_item_instance_corrected, true)

## 占位图新增物品实例时，仅同步派生缓存并转发信号。
func _on_occupy_map_item_instance_added(item_instance_data: ItemInstanceData) -> void:
	# 事务可在发布事件前整体同步缓存；事件仍需转发一次。
	if not item_instances.has(item_instance_data):
		item_instances.append(item_instance_data)
	item_added.emit(item_instance_data)

## 占位图移除物品实例时，仅同步派生缓存并转发信号。
func _on_occupy_map_item_instance_removed(
	item_instance_data: ItemInstanceData,
	removed_center_cell: Vector2i
) -> void:
	item_instances.erase(item_instance_data)
	item_removed.emit(item_instance_data)
	item_removed_in_cell.emit(item_instance_data, removed_center_cell)

## 占位图物品换位时，转发位置变化信号。
func _on_occupy_map_item_instance_position_changed(
	item_instance_data: ItemInstanceData,
	previous_cell: Vector2i
) -> void:
	item_position_changed.emit(item_instance_data, previous_cell)

## 占位图物品旋转时，转发旋转信号。
func _on_occupy_map_item_instance_rotated(item_instance_data: ItemInstanceData) -> void:
	item_rotated.emit(item_instance_data)

## 占位图物品轮廓变形时，转发变形信号。
func _on_occupy_map_item_instance_reshaped(item_instance_data: ItemInstanceData) -> void:
	item_reshaped.emit(item_instance_data)

## 占位图无法处理物品时，转发无法处理信号。
func _on_occupy_map_item_instance_cannot_be_handled(item_instance_data: ItemInstanceData) -> void:
	item_cannot_be_handled.emit(item_instance_data)

## 占位图物品校正成功时，转发校正成功信号。
func _on_occupy_map_item_instance_corrected(
	item_instance_data: ItemInstanceData,
	previous_cell: Vector2i
) -> void:
	item_corrected.emit(item_instance_data, previous_cell)

## 断开占位图资源上的变化信号。
func _disconnect_occupy_map_signals() -> void:
	if !occupy_map:
		return
	_set_occupy_map_signal_connection(occupy_map.map_changed, occupy_map_changed.emit, false)
	_set_occupy_map_signal_connection(occupy_map.item_instance_added, _on_occupy_map_item_instance_added, false)
	_set_occupy_map_signal_connection(occupy_map.item_instance_removed, _on_occupy_map_item_instance_removed, false)
	_set_occupy_map_signal_connection(occupy_map.item_instance_position_changed, _on_occupy_map_item_instance_position_changed, false)
	_set_occupy_map_signal_connection(occupy_map.item_instance_rotated, _on_occupy_map_item_instance_rotated, false)
	_set_occupy_map_signal_connection(occupy_map.item_instance_reshaped, _on_occupy_map_item_instance_reshaped, false)
	_set_occupy_map_signal_connection(occupy_map.item_instance_cannot_be_handled, _on_occupy_map_item_instance_cannot_be_handled, false)
	_set_occupy_map_signal_connection(occupy_map.item_instance_corrected, _on_occupy_map_item_instance_corrected, false)

## 根据目标状态设置占位图单条信号连接。
func _set_occupy_map_signal_connection(target_signal: Signal, target_callable: Callable, is_connect: bool) -> void:
	if is_connect:
		if !target_signal.is_connected(target_callable):
			target_signal.connect(target_callable)
	else:
		if target_signal.is_connected(target_callable):
			target_signal.disconnect(target_callable)

func init_occupy_map(cells: Array[Vector2i] = []) -> void:
	occupy_map.init_occupy_map(cells)
	revision += 1

## 以 occupancy 为准重建派生缓存（列表←occupancy）；冲突时 occupancy 胜出，不反向回填占用。
func ensure_occupancy_synced() -> void:
	if occupy_map == null:
		return
	occupy_map.rebuild_runtime_indexes()
	occupy_map.sync_placed_list_from_occupancy()
	item_instances = occupy_map.get_occupants_from_occupancy()
#endregion

## 只规划和裁决，不修改库存。
func plan_operation(request: InventoryOperationRequest) -> InventoryOperationDecision:
	return InventoryOperationPlanner.plan(request)

## 提交已经规划和裁决的单次 Plan。
func commit_operation(plan: InventoryOperationPlan) -> InventoryOperationResult:
	return InventoryOperationCommitter.commit(plan)

## 规划、裁决并提交一个操作意图。
func execute_operation(request: InventoryOperationRequest) -> InventoryOperationResult:
	var decision := plan_operation(request)
	if !decision.allowed:
		return InventoryOperationResult.failed(decision.reason_key, decision.plan)
	return commit_operation(decision.plan)

## 仅由 Committer 在整份方案写入完成、发出细粒度信号前调用。
func _advance_operation_revision() -> void:
	revision += 1

## 仅由 Committer 在整份方案的细粒度信号全部发出后调用。
func _emit_operation_committed(plan: InventoryOperationPlan) -> void:
	var result := InventoryOperationResult.succeeded(plan)
	operation_committed.emit(result)

#region occupy_map交互接口
## 尝试将背包外的物品放置到指定格子；若物品已在背包内,请使用 try_move_item_to_cell方法。
func try_place_item_in_cell(operation_context: InventoryOperationContext, item: ItemInstanceData, cell: Vector2i) -> bool:
	return try_place_item_quantity_in_cell(operation_context, item, cell, -1)


## 尝试把背包外实例中的精确数量原子放到指定格；部分数量由库存 Plan 内部拆分。
func try_place_item_quantity_in_cell(
	operation_context: InventoryOperationContext, item: ItemInstanceData, cell: Vector2i, quantity: int
) -> bool:
	var request := InventoryOperationRequest.create(operation_context, InventoryOperationRequest.Type.PLACE_AT, item)
	request.target_inventory = self
	request.target_cell = cell
	request.requested_quantity = quantity
	return execute_operation(request).success

## 尝试用输入物品替换目标格范围内的唯一物品，成功时返回被替换出的物品。
func try_replace_item_in_cell(operation_context: InventoryOperationContext, item: ItemInstanceData, cell: Vector2i) -> ItemInstanceData:
	var request := InventoryOperationRequest.create(operation_context, InventoryOperationRequest.Type.REPLACE_AT, item)
	request.target_inventory = self
	request.target_cell = cell
	var result := execute_operation(request)
	return result.replaced_item if result.success else null

## 尝试将物品与指定格子内的同种未满物品融合。
func try_merge_item_in_cell(operation_context: InventoryOperationContext, item: ItemInstanceData, cell: Vector2i) -> bool:
	return try_merge_item_quantity_in_cell(operation_context, item, cell, -1)


## 尝试把背包外实例中的精确数量原子合并到指定格。
func try_merge_item_quantity_in_cell(
	operation_context: InventoryOperationContext, item: ItemInstanceData, cell: Vector2i, quantity: int
) -> bool:
	var request := InventoryOperationRequest.create(operation_context, InventoryOperationRequest.Type.MERGE_AT, item)
	request.target_inventory = self
	request.target_cell = cell
	request.requested_quantity = quantity
	return execute_operation(request).success

## 尝试添加物品，不与现有物品进行融合
func try_add_item_without_merge(operation_context: InventoryOperationContext, item: ItemInstanceData) -> bool:
	var request := InventoryOperationRequest.create(operation_context,
		InventoryOperationRequest.Type.ADD_WITHOUT_MERGE, item
	)
	request.target_inventory = self
	return execute_operation(request).success

## 尝试将已在背包内的物品移动到指定格子。
func try_move_item_to_cell(operation_context: InventoryOperationContext, item: ItemInstanceData, cell: Vector2i) -> bool:
	var request := InventoryOperationRequest.create(operation_context, InventoryOperationRequest.Type.MOVE_WITHIN, item)
	request.source_inventory = self
	request.target_inventory = self
	request.target_cell = cell
	return execute_operation(request).success

## 尝试旋转背包中的物品（默认顺时针 90 度）。
func try_rotate_item_in_inventory(operation_context: InventoryOperationContext, item_instance_data: ItemInstanceData, rotate_step: int = 1) -> bool:
	var request := InventoryOperationRequest.create(operation_context,
		InventoryOperationRequest.Type.ROTATE, item_instance_data
	)
	request.source_inventory = self
	request.target_inventory = self
	request.rotate_step = rotate_step
	return execute_operation(request).success

## 尽力旋转背包中的物品，依次尝试 90°、180°、270° 旋转。
func try_rotate_item_in_inventory_best_effort(operation_context: InventoryOperationContext, item_instance_data: ItemInstanceData) -> bool:
	for rotate_step in [1, 2, 3]:
		if try_rotate_item_in_inventory(operation_context, item_instance_data, rotate_step):
			return true
	return false

## 从背包中拿出特定物品
func try_take_item(operation_context: InventoryOperationContext, item: ItemInstanceData) -> bool:
	var request := InventoryOperationRequest.create(operation_context, InventoryOperationRequest.Type.TAKE, item)
	request.source_inventory = self
	return execute_operation(request).success

## 尝试永久结束本库存对指定完整物品实例的所有权；成功后不产生操作产物。
func try_destroy_item(operation_context: InventoryOperationContext, item: ItemInstanceData) -> bool:
	var request := InventoryOperationRequest.create(operation_context,
		InventoryOperationRequest.Type.DESTROY, item
	)
	request.source_inventory = self
	return execute_operation(request).success

## 从背包成员中取出指定数量；整堆时返回原实例，部分时返回新拆出的实例。
func try_take_item_quantity(operation_context: InventoryOperationContext, item: ItemInstanceData, quantity: int) -> ItemInstanceData:
	var request := InventoryOperationRequest.create(operation_context, InventoryOperationRequest.Type.TAKE, item)
	request.source_inventory = self
	request.requested_quantity = quantity
	var result := execute_operation(request)
	return result.output_item if result.success else null

## 向背包内添加物品，并与现有同种未满物品尝试合并。
func try_add_item_with_merge(operation_context: InventoryOperationContext, item: ItemInstanceData) -> bool:
	return try_add_item_quantity_with_merge(operation_context, item, -1)


## 精确放入指定数量；先自动合并，剩余量再整体寻位，全部属于同一 Plan。
func try_add_item_quantity_with_merge(operation_context: InventoryOperationContext, item: ItemInstanceData, quantity: int) -> bool:
	var request := InventoryOperationRequest.create(operation_context,
		InventoryOperationRequest.Type.ADD_WITH_MERGE, item
	)
	request.target_inventory = self
	request.requested_quantity = quantity
	return execute_operation(request).success

## 从背包中拿出物品
func try_take_same_item(operation_context: InventoryOperationContext, item_data: ItemData) -> ItemInstanceData:
	var same_items = get_item_instance_datas_from_item_data(item_data)
	if !same_items.is_empty():
		var take_item = same_items.pop_front()
		if try_take_item(operation_context, take_item):
			return take_item
	return null

## 清除所有物品（先清 occupancy，再对齐派生缓存）。
func clear_contents_for_restore() -> void:
	if occupy_map == null:
		return
	if get_item_instances().is_empty():
		item_instances.clear()
		return
	occupy_map.clear_occupancy()
	item_instances.clear()
	occupy_map.unplaced_item_instances.clear()
	revision += 1
	inventory_cleared.emit()

#endregion

#region 整理流程
## 整理背包
func _sort(operation_context: InventoryOperationContext):
	_merge_all_same_items_via_operations(operation_context)

## 尝试整理背包，成功后会发出 sorted 信号。
func try_sort_inventory(operation_context: InventoryOperationContext) -> bool:
	if get_item_instances().is_empty():
		return false
	_sort(operation_context)
	var first_item := get_item_instances()[0]
	var request := InventoryOperationRequest.create(operation_context,
		InventoryOperationRequest.Type.RELAYOUT, first_item
	)
	request.source_inventory = self
	request.target_inventory = self
	if !execute_operation(request).success:
		return false
	sorted.emit()
	return true

## 整理阶段的合并仍逐项经过统一 Plan；被规则阻止的来源堆保持原样。
func _merge_all_same_items_via_operations(operation_context: InventoryOperationContext) -> void:
	for target in get_item_instances().duplicate():
		if target == null or target.is_full() or !has_item_instance(target):
			continue
		for source in get_item_instances().duplicate():
			if source == null or source == target or !has_item_instance(source):
				continue
			if !target.can_merge_item(source):
				continue
			var target_cell := occupy_map.get_item_center_cell(target)
			if target_cell != Vector2i(-1, -1):
				try_merge_item_in_cell(operation_context, source, target_cell)
			if target.is_full():
				break
#endregion

#region 查询接口
## 获取背包成员（权威：occupancy 占据者；不含 unplaced）。
func get_item_instances() -> Array[ItemInstanceData]:
	if occupy_map == null:
		return []
	return occupy_map.get_occupants_from_occupancy()

## 获取背包占位图资源。
func get_occupy_map() -> InventoryOccupyMap:
	return occupy_map

## 获取物品在指定中心格的放置预览格子（委托占位图）。
func get_preview_cells_for_item(
	item_instance_data: ItemInstanceData,
	center_cell: Vector2i
) -> Array[Vector2i]:
	if occupy_map == null:
		return []
	return occupy_map.get_preview_cells_for_item(item_instance_data, center_cell)

## 获取背包内所有拥有 item_data 数据的背包物品数量
func get_item_instance_num_from_item_data(item_data: ItemData) -> int:
	var num: int = 0
	for item_in_inventory in get_item_instances():
		if item_in_inventory.item_data == item_data:
			num += 1
	return num

## 获取背包内所有拥有 item_data 数据的物品总数量（num 求和）。
func get_item_total_num_from_item_data(item_data: ItemData) -> int:
	var total_num: int = 0
	for item_in_inventory in get_item_instances():
		if item_in_inventory.item_data == item_data:
			total_num += item_in_inventory.num
	return total_num

## 获取背包内所有拥有 item_data 数据的背包物品数据
func get_item_instance_datas_from_item_data(item_data: ItemData) -> Array[ItemInstanceData]:
	var same_items: Array[ItemInstanceData]
	for item_in_inventory in get_item_instances():
		if item_in_inventory.item_data == item_data:
			same_items.append(item_in_inventory)
	return same_items

## 获取背包内种类、轮廓阶段均相同且堆叠未满的物品
func get_unfull_same_items(item: ItemInstanceData) -> Array[ItemInstanceData]:
	var unfull_items: Array[ItemInstanceData]
	for item_in_inventory in get_item_instances():
		if item_in_inventory.is_same_item(item) and item_in_inventory.num < item.get_item_max_num():
			unfull_items.append(item_in_inventory)
	return unfull_items

## 获取背包内种类相同且堆叠未满的物品
func get_unfull_items() -> Array[ItemInstanceData]:
	var unfull_items: Array[ItemInstanceData]
	for item in get_item_instances():
		if item.num < item.get_item_max_num():
			unfull_items.append(item)
	return unfull_items
#endregion

#region 基础判断
## 背包数据中是否有此类物品
func has_item_data(item_data: ItemData) -> bool:
	for item_in_inventory in get_item_instances():
		if item_in_inventory.item_data == item_data:
			return true
	return false

## 背包数据中是否有该物品实例数据（以 occupancy 为准）。
func has_item_instance(item_instance: ItemInstanceData) -> bool:
	if occupy_map == null:
		return false
	return occupy_map.has_item_instance_in_occupancy(item_instance)

## 该物品是否能够拿取
func can_take_item(operation_context: InventoryOperationContext, _item_instance_data: ItemInstanceData) -> bool:
	var request := InventoryOperationRequest.create(operation_context,
		InventoryOperationRequest.Type.TAKE, _item_instance_data
	)
	request.source_inventory = self
	return plan_operation(request).allowed

## 判断背包中的物品是否能够按指定步数旋转。
func can_rotate_item_in_inventory(operation_context: InventoryOperationContext, item_instance_data: ItemInstanceData, rotate_step: int = 1) -> bool:
	var request := InventoryOperationRequest.create(operation_context,
		InventoryOperationRequest.Type.ROTATE, item_instance_data
	)
	request.source_inventory = self
	request.target_inventory = self
	request.rotate_step = rotate_step
	return plan_operation(request).allowed

#endregion

#region occupy_map 委托判断
## 判断背包是否已满
func is_full() -> bool:
	return occupy_map.is_full()

## 判断背包是否能够添加该物品
func can_add_item(operation_context: InventoryOperationContext, item: ItemInstanceData) -> bool:
	var request := InventoryOperationRequest.create(operation_context,
		InventoryOperationRequest.Type.ADD_WITH_MERGE, item
	)
	request.target_inventory = self
	return plan_operation(request).allowed

## 判断背包是否能够直接添加该物品（不进行融合）。
func can_add_item_without_merge(operation_context: InventoryOperationContext, item: ItemInstanceData) -> bool:
	var request := InventoryOperationRequest.create(operation_context,
		InventoryOperationRequest.Type.ADD_WITHOUT_MERGE, item
	)
	request.target_inventory = self
	return plan_operation(request).allowed

## 判断指定格子中的目标物品是否可以与传入物品融合。
func can_merge_item_in_cell(operation_context: InventoryOperationContext, item: ItemInstanceData, cell: Vector2i) -> bool:
	return can_merge_item_quantity_in_cell(operation_context, item, cell, -1)


func can_merge_item_quantity_in_cell(
	operation_context: InventoryOperationContext, item: ItemInstanceData, cell: Vector2i, quantity: int
) -> bool:
	var request := InventoryOperationRequest.create(operation_context, InventoryOperationRequest.Type.MERGE_AT, item)
	request.target_inventory = self
	request.target_cell = cell
	request.requested_quantity = quantity
	return plan_operation(request).allowed

## 判断指定格子是否可以放置该物品。
func can_place_item_in_cell(operation_context: InventoryOperationContext, item: ItemInstanceData, cell: Vector2i) -> bool:
	return can_place_item_quantity_in_cell(operation_context, item, cell, -1)


func can_place_item_quantity_in_cell(
	operation_context: InventoryOperationContext, item: ItemInstanceData, cell: Vector2i, quantity: int
) -> bool:
	var request := InventoryOperationRequest.create(operation_context, InventoryOperationRequest.Type.PLACE_AT, item)
	request.target_inventory = self
	request.target_cell = cell
	request.requested_quantity = quantity
	return plan_operation(request).allowed

## 判断指定格子是否可以被该物品替换放置。
func can_replace_item_in_cell(operation_context: InventoryOperationContext, item: ItemInstanceData, cell: Vector2i) -> bool:
	var request := InventoryOperationRequest.create(operation_context, InventoryOperationRequest.Type.REPLACE_AT, item)
	request.target_inventory = self
	request.target_cell = cell
	return plan_operation(request).allowed
#endregion
