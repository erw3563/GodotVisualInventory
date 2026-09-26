@tool
class_name FreeItemsPanel
extends Control
## 自由格物品面板：FREE 形式层的共享显示部件。
## 每个物品实例（堆）生成一个 FreeItemCell；面板只负责生成 / 销毁 / 跟踪格子与命中检测，
## 不管理格子的最终排布——具体子类 Definition（如 ORBIT）可把挂载接缝 cell_parent
## 指到自身创建的布局节点（如环形轨道），格子直接生在其名下、位置由其管理；
## 未接管时格子挂在面板 CellsBox 下做顺序流式排布兜底。
## 命中检测对每格使用逆全局变换，格子随布局节点旋转后依然正确。
## 指针事件统一由面板根节点接收并转发给 FreeItemsInputController 处理。
## 显示尺寸口径：形状背包（ShapeInventoryOccupyMap）按形状包围盒放大，非形状背包恒 1×1。

## 背包数据（标准 InventoryData，无 FREE 专属数据类）。
@export var inventory_data: InventoryData:
	set(value):
		_try_disconnect_inventory_data_signal()
		inventory_data = value
		if !is_node_ready():
			await ready
		_apply_inventory_data_binding()

## 单元格尺寸（一格的像素大小；由布局 Definition 经 Host Context 下发）。
@export var cell_size := Vector2(48, 48)
## 兜底流式排布的行宽（格子生在面板自身容器下时按此宽度换行）。
@export var fallback_flow_width := 240.0
## 兜底流式排布的格间距。
@export var fallback_flow_gap := 8.0
## 是否接收指针交互。
## 面板最小尺寸（无格子时的期望尺寸兜底）。
@export var min_panel_size := Vector2(216.0, 96.0)

## 物品实例 → 格子注册表。
var _item_to_cell: Dictionary[ItemInstanceData, FreeItemCell] = {}
## 外部出生父节点：非空时格子直接生到该节点名下（位置归外部 UI 管理，不参与兜底排布）；
## 由具体子类 Definition（如 ORBIT）在装配内部绑定，变化时全量重建使新格子生在新父节点下。
var cell_parent: Node = null:
	set(value):
		var normalized := value if is_instance_valid(value) else null
		if cell_parent == normalized:
			return
		cell_parent = normalized
		_rebuild_cells_for_cell_parent_change()
## 默认格子容器（兜底流式排布的挂载父节点）。
var _cells_box: Control
## 绑定的输入控制器。
var _items_input_controller: FreeItemsInputController
## 当前悬停高亮的格子。
var _hovered_cell: FreeItemCell
## 实例格底板样式；空值表示透明底板。
var cell_style: StyleBox = null
## 是否绘制实例格底板。
var show_cell_background := true
## 已连接 changed 的样式资源，便于刷新时断开。
var _watched_styles: Array[StyleBox] = []


func _ready() -> void:
	_ensure_ui_nodes()
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 在默认优先级的外部布局更新之后同步悬停。
	process_priority = 1
	if !gui_input.is_connected(_on_gui_input):
		gui_input.connect(_on_gui_input)
	if !mouse_entered.is_connected(_on_pointer_entered):
		mouse_entered.connect(_on_pointer_entered)
	if !mouse_exited.is_connected(_on_pointer_exited):
		mouse_exited.connect(_on_pointer_exited)
	_apply_inventory_data_binding()


func _exit_tree() -> void:
	_disconnect_style_watchers()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_update_hovered_cell()
	if is_instance_valid(_items_input_controller):
		_items_input_controller.refresh_mouse_pointed_item()


## 具体布局注入通用布局节点；物品、手持放置、快捷键和遮挡 UI 优先。
func can_begin_layout_drag(event: InputEventMouseButton) -> bool:
	if event.shift_pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return false
	if get_viewport().gui_get_hovered_control() != self:
		return false
	if is_instance_valid(_items_input_controller) and _items_input_controller.has_taking_item():
		return false
	var canvas_position := get_canvas_transform().affine_inverse() * event.position
	return get_item_at_position(canvas_position) == null


## 下发实例格底板样式，并刷新已有格子。
func configure_cell_presentation(
	next_cell_style: StyleBox,
	next_show_cell_background: bool
) -> void:
	var style_changed := (
		cell_style != next_cell_style
		or show_cell_background != next_show_cell_background
	)
	cell_style = next_cell_style
	show_cell_background = next_show_cell_background
	_reconnect_style_watchers()
	_diagnose_style_minimum(cell_style)
	if style_changed:
		_refresh_existing_cell_styles()


## 连接样式资源变化，编辑嵌套 StyleBox 时刷新实例格底板。
func _reconnect_style_watchers() -> void:
	_disconnect_style_watchers()
	if cell_style == null:
		return
	if not cell_style.changed.is_connected(_on_cell_style_changed):
		cell_style.changed.connect(_on_cell_style_changed)
	_watched_styles.append(cell_style)


func _disconnect_style_watchers() -> void:
	for style in _watched_styles:
		if is_instance_valid(style) and style.changed.is_connected(_on_cell_style_changed):
			style.changed.disconnect(_on_cell_style_changed)
	_watched_styles.clear()


func _on_cell_style_changed() -> void:
	_diagnose_style_minimum(cell_style)
	_refresh_existing_cell_styles()


## 样式最小尺寸超过约定格子尺寸时输出诊断。
func _diagnose_style_minimum(style: StyleBox) -> void:
	if style == null:
		return
	var minimum := style.get_minimum_size()
	if minimum.x > cell_size.x or minimum.y > cell_size.y:
		push_error(
			"FREE: StyleBox 最小尺寸 %s 超过格子尺寸 %s" % [str(minimum), str(cell_size)]
		)


## 仅刷新已有实例格底板样式。
func _refresh_existing_cell_styles() -> void:
	for cell in _item_to_cell.values():
		if is_instance_valid(cell):
			cell.configure_background(cell_style, show_cell_background)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# 面板销毁时，生在外部父节点名下的格子不会随面板子树释放，需要显式清理避免孤儿格子。
		for cell in _item_to_cell.values():
			if is_instance_valid(cell) and cell.get_parent() != _cells_box:
				cell.queue_free()


#region 数据绑定与刷新

## 设置背包数据并刷新显示。
func set_inventory_data(inventory_data_: InventoryData) -> void:
	inventory_data = inventory_data_


## 连接背包信号并全量重建格子。
func _apply_inventory_data_binding() -> void:
	_try_connect_inventory_data_signal()
	_try_update_all_cells()


## 强制刷新全部格子（数据引用未变时也可调用）。
func refresh_display() -> void:
	_try_update_all_cells()


func _try_connect_inventory_data_signal() -> void:
	if !inventory_data:
		return
	_set_inventory_data_signals(true)


func _try_disconnect_inventory_data_signal() -> void:
	if !inventory_data:
		return
	_set_inventory_data_signals(false)


## 统一处理背包数据相关信号的连接与断开。
func _set_inventory_data_signals(is_connect: bool) -> void:
	_set_signal_connection(inventory_data.item_added, _try_create_cell_on_inventory_item_added, is_connect)
	_set_signal_connection(inventory_data.item_removed, _try_erase_cell_on_inventory_item_removed, is_connect)
	_set_signal_connection(inventory_data.item_position_changed, _try_sync_cell_display, is_connect)
	_set_signal_connection(inventory_data.item_corrected, _try_sync_cell_display, is_connect)
	_set_signal_connection(inventory_data.item_rotated, _try_sync_cell_display, is_connect)
	_set_signal_connection(inventory_data.item_reshaped, _try_sync_cell_display, is_connect)
	_set_signal_connection(inventory_data.sorted, _try_update_all_cells, is_connect)
	_set_signal_connection(inventory_data.inventory_cleared, _try_update_all_cells, is_connect)
	_set_signal_connection(inventory_data.occupy_map_changed, _try_update_all_cells, is_connect)
	_set_signal_connection(inventory_data.item_cannot_be_handled, _try_erase_cell_on_inventory_item_removed, is_connect)


## 根据目标状态设置单条信号连接，避免重复连接。
func _set_signal_connection(target_signal: Signal, target_callable: Callable, is_connect: bool) -> void:
	if is_connect:
		if !target_signal.is_connected(target_callable):
			target_signal.connect(target_callable)
	else:
		if target_signal.is_connected(target_callable):
			target_signal.disconnect(target_callable)

#endregion


#region 格子生成与销毁

## 全量重建：先清空再为每个可显示物品实例建格。
func _try_update_all_cells() -> void:
	clear_all_cells()
	if inventory_data:
		for item_instance_data in inventory_data.get_item_instances():
			_try_create_cell_on_inventory_item_added(item_instance_data)


## 物品加入背包时创建对应格子（已存在或不可显示时跳过），挂到当前出生父节点名下。
func _try_create_cell_on_inventory_item_added(item_instance_data: ItemInstanceData) -> void:
	if !_can_display_item_instance(item_instance_data):
		return
	if _item_to_cell.has(item_instance_data):
		return
	var cell := _create_cell(item_instance_data)
	_get_cell_birth_parent().add_child(cell)
	if !_is_external_cell_parent_active():
		_apply_fallback_positions()


## 物品移除背包时释放对应格子。
func _try_erase_cell_on_inventory_item_removed(item_instance_data: ItemInstanceData) -> void:
	if !_item_to_cell.has(item_instance_data):
		return
	var cell: FreeItemCell = _item_to_cell[item_instance_data]
	_item_to_cell.erase(item_instance_data)
	if _hovered_cell == cell:
		_hovered_cell = null
	cell.queue_free()
	_apply_fallback_positions()


## 位置 / 校正 / 旋转 / 变形时同步格子显示（覆盖从不可显示变为可显示的创建与反向销毁）。
func _try_sync_cell_display(item_instance_data: ItemInstanceData, _previous_cell: Vector2i = Vector2i.ZERO) -> void:
	if !_can_display_item_instance(item_instance_data):
		_try_erase_cell_on_inventory_item_removed(item_instance_data)
		return
	if !_item_to_cell.has(item_instance_data):
		_try_create_cell_on_inventory_item_added(item_instance_data)
		return
	var cell: FreeItemCell = _item_to_cell[item_instance_data]
	if is_instance_valid(cell):
		cell.refresh_display()
		_apply_fallback_positions()


## 创建格子并登记注册表。
func _create_cell(item_instance_data: ItemInstanceData) -> FreeItemCell:
	var cell := FreeItemCell.new()
	cell.configure_background(cell_style, show_cell_background)
	cell.init_item(item_instance_data, cell_size, _should_follow_shape())
	cell.icon_view.set_sync_callback(_sync_item_view)
	_item_to_cell[item_instance_data] = cell
	return cell


## 清除全部格子（外部父节点名下的格子一并显式释放）。
func clear_all_cells() -> void:
	for cell in _item_to_cell.values():
		if !is_instance_valid(cell):
			continue
		cell.queue_free()
	_item_to_cell.clear()
	_hovered_cell = null


## 出生父节点变化时全量重建：旧格子释放、新格子生在新父节点名下（无格子时仅记录，后续新格子直接生效）。
func _rebuild_cells_for_cell_parent_change() -> void:
	if !is_node_ready():
		await ready
	if _item_to_cell.is_empty():
		return
	_try_update_all_cells()

#endregion


#region 判断

## 判断物品实例是否应显示：锚点可定位且物品实际占格。
## 锚点可能是环形空洞，甚至被另一物品占用，不能用锚点格验证归属。
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


## 形状背包按形状包围盒放大格子；非形状背包恒 1×1。
func _should_follow_shape() -> bool:
	if !inventory_data:
		return true
	var occupy_map := inventory_data.get_occupy_map()
	if occupy_map == null:
		return true
	return !(occupy_map is NonShapeInventoryOccupyMap)

#endregion


#region 兜底排布与查询

## 只重排挂在面板自身 CellsBox 下的格子（顺序流式换行）；外部父节点名下的格子不干涉。
func _apply_fallback_positions() -> void:
	if !is_instance_valid(_cells_box):
		return
	var cursor := Vector2.ZERO
	var row_height := 0.0
	for cell in _item_to_cell.values():
		if !is_instance_valid(cell) or cell.get_parent() != _cells_box:
			continue
		if cursor.x > 0.0 and cursor.x + cell.size.x > maxf(fallback_flow_width, cell.size.x):
			cursor.x = 0.0
			cursor.y += row_height + fallback_flow_gap
			row_height = 0.0
		cell.position = cursor
		cursor.x += cell.size.x + fallback_flow_gap
		row_height = maxf(row_height, cell.size.y)


## 格子出生父节点：外部节点有效时用它，否则面板自身的 CellsBox。
func _get_cell_birth_parent() -> Node:
	if _is_external_cell_parent_active():
		return cell_parent
	_ensure_ui_nodes()
	return _cells_box


## 外部出生父节点是否生效（已设置且仍有效）。
func _is_external_cell_parent_active() -> bool:
	return cell_parent != null and is_instance_valid(cell_parent)


## 当前全部有效格子（注册表顺序）。
func get_cells() -> Array:
	var cells: Array = []
	for cell in _item_to_cell.values():
		if is_instance_valid(cell):
			cells.append(cell)
	return cells


## 按物品实例取格子（不存在或已释放时返回 null）。
func get_cell_for_item(item_instance_data: ItemInstanceData) -> FreeItemCell:
	var cell: FreeItemCell = _item_to_cell.get(item_instance_data)
	if is_instance_valid(cell):
		return cell
	return null


## 默认格子容器（未配置外部出生父节点时格子的挂载父节点）。
func get_cells_container() -> Control:
	return _cells_box


## 手持物品视图使用的格子尺寸参考。
func get_free_cell_size() -> Vector2:
	return cell_size


## 面板期望尺寸（按当前格子包围盒估算，供宿主同步最小尺寸用）。
func get_free_preferred_size() -> Vector2:
	var bounds := Rect2(Vector2.ZERO, min_panel_size)
	var panel_origin := get_global_rect().position
	for cell in get_cells():
		if !cell.is_inside_tree():
			continue
		var cell_rect: Rect2 = cell.get_global_rect()
		var local_rect := Rect2(cell_rect.position - panel_origin, cell_rect.size)
		bounds = bounds.merge(local_rect)
	return bounds.size

#endregion


#region 指针交互

## 绑定自由格输入控制器（面板统一接收 gui_input 后转发）。
func bind_items_input_controller(controller: FreeItemsInputController) -> void:
	if _items_input_controller == controller:
		return
	_items_input_controller = controller
	if is_instance_valid(_items_input_controller) and _items_input_controller.free_panel == null:
		_items_input_controller.free_panel = self


func _on_gui_input(event: InputEvent) -> void:
	if !is_instance_valid(_items_input_controller):
		return
	_items_input_controller.activate_input()
	if event is InputEventMouseMotion:
		_update_hovered_cell()
		_items_input_controller.refresh_mouse_pointed_item()
		return
	if event is InputEventMouseButton:
		var mouse_button_event := event as InputEventMouseButton
		if _items_input_controller.handle_pointer_input(mouse_button_event):
			accept_event()


func _on_pointer_entered() -> void:
	if is_instance_valid(_items_input_controller):
		_items_input_controller.activate_input()


func _on_pointer_exited() -> void:
	if is_instance_valid(_items_input_controller):
		_items_input_controller.refresh_mouse_pointed_item()
		_items_input_controller.deactivate_input()


## 外部布局的可见物品可能越过面板矩形；GUI 接收区域与物品命中保持一致。
func _has_point(point: Vector2) -> bool:
	if Rect2(Vector2.ZERO, size).has_point(point):
		return true
	return _find_cell_at_position(get_global_transform() * point) != null


## 鼠标是否在面板或外部布局的可见物品上。
func is_mouse_in_panel() -> bool:
	return is_visible_in_tree() and _has_point(get_local_mouse_position())


## 鼠标所在格子的物品实例；不在任何格子上时返回 null。
func get_item_under_mouse() -> ItemInstanceData:
	return get_item_at_position(get_global_mouse_position())


## 指定全局坐标所在格子的物品实例；不在任何格子上时返回 null。
## 对每格使用逆全局变换做局部矩形检测，格子随外部节点旋转后依然正确。
func get_item_at_position(global_pos: Vector2) -> ItemInstanceData:
	var cell := _find_cell_at_position(global_pos)
	if cell == null:
		return null
	return cell.get_item_instance_data()


## 指定全局坐标所在的格子（后创建者优先，覆盖重叠时取最上层）。
func _find_cell_at_position(global_pos: Vector2) -> FreeItemCell:
	var cells := get_cells()
	for index in range(cells.size() - 1, -1, -1):
		var cell: FreeItemCell = cells[index]
		if _is_cell_hit_at_position(cell, global_pos):
			return cell
	return null


func _is_cell_hit_at_position(cell: FreeItemCell, global_pos: Vector2) -> bool:
	if !is_instance_valid(cell) or !cell.is_inside_tree() or cell.is_queued_for_deletion() \
			or !cell.is_visible_in_tree():
		return false
	var local_pos := cell.get_global_transform().affine_inverse() * global_pos
	return Rect2(Vector2.ZERO, cell.size).has_point(local_pos)


## 刷新悬停格子高亮。
func _update_hovered_cell() -> void:
	var new_cell: FreeItemCell = null
	if is_mouse_in_panel() and get_viewport().gui_get_hovered_control() == self:
		new_cell = _find_cell_at_position(get_global_mouse_position())
	if new_cell == _hovered_cell:
		return
	if is_instance_valid(_hovered_cell):
		_hovered_cell.set_highlighted(false)
	_hovered_cell = new_cell
	if is_instance_valid(_hovered_cell):
		_hovered_cell.set_highlighted(true)


## 确保 UI 节点存在，支持纯代码创建。
func _ensure_ui_nodes() -> void:
	if is_instance_valid(_cells_box):
		return
	_cells_box = get_node_or_null("CellsBox") as Control
	if !is_instance_valid(_cells_box):
		_cells_box = Control.new()
		_cells_box.name = "CellsBox"
		_cells_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_cells_box)

#endregion


var _view_provider: InventoryItemViewProvider

func set_view_provider(provider: InventoryItemViewProvider) -> void:
	_view_provider = provider
	for cell in _item_to_cell.values():
		if is_instance_valid(cell) and is_instance_valid(cell.icon_view):
			cell.icon_view.set_sync_callback(_sync_item_view)

func _sync_item_view(item: ItemInstanceData, view: ItemIconView) -> void:
	if _view_provider != null:
		_view_provider.sync_view(item, view)

func get_item_views(item: ItemInstanceData) -> Array[ItemIconView]:
	var cell = _item_to_cell.get(item)
	if is_instance_valid(cell) and not cell.is_queued_for_deletion() and cell.icon_view.get_bound_item() == item:
		return [cell.icon_view]
	return []
