@tool
class_name InventoryGridPanel
extends GridContainer

#region 信号
signal updated
## 格子尺寸变化时发出。
signal cell_size_changed
#endregion

#region 导出属性与变量
@export var cell_size: Vector2 = Vector2(32, 32):
	set(value):
		if cell_size == value:
			return
		cell_size = value
		_diagnose_style_minimum(cell_style)
		_diagnose_style_minimum(empty_cell_style)
		update_cell()
		cell_size_changed.emit()
## 背包数据，网格面板可直接与其占位图交互。
@export var inventory_data: InventoryData:
	set(value):
		_try_disconnect_inventory_data_signal()
		inventory_data = value
		if !is_node_ready():
			await ready
		_try_connect_inventory_data_signal()
		sync_from_inventory_data()

## 合法区域底板样式；空值表示透明底板。
var cell_style: StyleBox = null
## 空洞格子装饰样式；空值表示透明占位。
var empty_cell_style: StyleBox = null
## 合法格与空洞格是否绘制底板。
var show_cell_background: bool = true
## 格子水平、垂直间距；同步写入 GridContainer 主题常量。
var cell_spacing: Vector2i = Vector2i(4, 4)

var is_mouse_in: bool
var cell_panels: Array[Control]
## 当前网格边界尺寸（由 OccupyMap 推导）。
var grid_size: Vector2i = Vector2i.ZERO
## 网格索引对应的 OccupyMap 坐标原点，固定从 (0, 0) 开始。
var region_origin: Vector2i = Vector2i.ZERO
## 绑定的背包输入控制器，由 gui_input 转发指针事件。
var _items_input_controller: InventoryItemsInputController
## 已连接 changed 的样式资源，便于刷新时断开。
var _watched_styles: Array[StyleBox] = []
#endregion

#region 生命周期
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_cell_spacing_theme()
	if !mouse_entered.is_connected(_on_mouse_entered_grid):
		mouse_entered.connect(_on_mouse_entered_grid)
	if !mouse_exited.is_connected(_on_mouse_exited_grid):
		mouse_exited.connect(_on_mouse_exited_grid)
	_try_connect_inventory_data_signal()
	sync_from_inventory_data()


func _exit_tree() -> void:
	_disconnect_style_watchers()
#endregion

#region 外观配置
## 下发底板样式与间距，并按当前库存重建格子。
func configure_presentation(
	next_cell_style: StyleBox,
	next_empty_cell_style: StyleBox,
	next_show_cell_background: bool,
	next_cell_spacing: Vector2i
) -> void:
	var spacing := Vector2i(maxi(next_cell_spacing.x, 0), maxi(next_cell_spacing.y, 0))
	var style_changed := (
		cell_style != next_cell_style
		or empty_cell_style != next_empty_cell_style
		or show_cell_background != next_show_cell_background
	)
	var spacing_changed := cell_spacing != spacing
	cell_style = next_cell_style
	empty_cell_style = next_empty_cell_style
	show_cell_background = next_show_cell_background
	cell_spacing = spacing
	_apply_cell_spacing_theme()
	_reconnect_style_watchers()
	_diagnose_style_minimum(cell_style)
	_diagnose_style_minimum(empty_cell_style)
	if style_changed or spacing_changed:
		update_cell()


## 将间距写入 GridContainer 主题常量，驱动容器排布。
func _apply_cell_spacing_theme() -> void:
	add_theme_constant_override("h_separation", cell_spacing.x)
	add_theme_constant_override("v_separation", cell_spacing.y)


## 连接样式资源变化，编辑嵌套 StyleBox 时刷新底板。
func _reconnect_style_watchers() -> void:
	_disconnect_style_watchers()
	for style in [cell_style, empty_cell_style]:
		if style == null:
			continue
		if not style.changed.is_connected(_on_cell_style_changed):
			style.changed.connect(_on_cell_style_changed)
		_watched_styles.append(style)


func _disconnect_style_watchers() -> void:
	for style in _watched_styles:
		if is_instance_valid(style) and style.changed.is_connected(_on_cell_style_changed):
			style.changed.disconnect(_on_cell_style_changed)
	_watched_styles.clear()


func _on_cell_style_changed() -> void:
	_diagnose_style_minimum(cell_style)
	_diagnose_style_minimum(empty_cell_style)
	_refresh_existing_cell_styles()


## 样式最小尺寸超过约定格子尺寸时输出诊断。
func _diagnose_style_minimum(style: StyleBox) -> void:
	if style == null:
		return
	var minimum := style.get_minimum_size()
	if minimum.x > cell_size.x or minimum.y > cell_size.y:
		push_error(
			"GRID: StyleBox 最小尺寸 %s 超过格子尺寸 %s" % [str(minimum), str(cell_size)]
		)


## 仅刷新已有格子样式，保留当前排布节点。
func _refresh_existing_cell_styles() -> void:
	var occupy_map := _get_occupy_map()
	if occupy_map == null or cell_panels.is_empty():
		return
	var panel_index := 0
	for cell_y in range(grid_size.y):
		for cell_x in range(grid_size.x):
			if panel_index >= cell_panels.size():
				return
			var cell_patch := cell_panels[panel_index] as NinePatchRect
			panel_index += 1
			if cell_patch == null:
				continue
			var occupy_cell := Vector2i(cell_x, cell_y)
			if occupy_map.has_region_cell(occupy_cell):
				InventoryStyleBoxNinePatch.apply(cell_patch, cell_style, show_cell_background)
			else:
				InventoryStyleBoxNinePatch.apply(cell_patch, empty_cell_style, show_cell_background)
#endregion

#region 输入绑定
## 绑定背包输入控制器，由本面板统一接收 gui_input 并转发。
func bind_items_input_controller(controller: InventoryItemsInputController) -> void:
	if _items_input_controller == controller:
		return
	if is_instance_valid(_items_input_controller) and gui_input.is_connected(_on_gui_input):
		gui_input.disconnect(_on_gui_input)
	_items_input_controller = controller
	if is_instance_valid(_items_input_controller) and !gui_input.is_connected(_on_gui_input):
		gui_input.connect(_on_gui_input)

func _on_gui_input(event: InputEvent) -> void:
	if !is_instance_valid(_items_input_controller):
		return
	_items_input_controller.activate_input(self)
	if event is InputEventMouseMotion:
		is_mouse_in = true
		_items_input_controller.refresh_mouse_pointed_item(self)
		return
	if event is InputEventMouseButton:
		var mouse_button_event := event as InputEventMouseButton
		if _items_input_controller.handle_pointer_input(mouse_button_event, self):
			accept_event()

## 鼠标进入网格。
func _on_mouse_entered_grid() -> void:
	is_mouse_in = true
	if is_instance_valid(_items_input_controller):
		_items_input_controller.activate_input(self)

## 鼠标离开网格时刷新悬停指向状态。
func _on_mouse_exited_grid() -> void:
	is_mouse_in = false
	if is_instance_valid(_items_input_controller):
		_items_input_controller.refresh_mouse_pointed_item(self)
		_items_input_controller.deactivate_input()
#endregion

#region 网格构建
## 根据 OccupyMap 更新背包格子。
func update_cell():
	_clear_cell_panels()
	var occupy_map := _get_occupy_map()
	if occupy_map:
		_build_cells_from_occupy_map(occupy_map)
	else:
		_reset_grid_state()
	updated.emit()

## 清理当前所有格子控件。
func _clear_cell_panels() -> void:
	while cell_panels.size() != 0:
		var cell_panel = cell_panels.pop_back()
		cell_panel.queue_free()

## 从 (0, 0) 到边界最大值遍历并生成格子；合法区域与空洞均创建 NinePatchRect。
func _build_cells_from_occupy_map(occupy_map: OccupyMap) -> void:
	var region_cells := occupy_map.get_region_cells()
	if region_cells.is_empty():
		_reset_grid_state()
		return

	var max_x := region_cells[0].x
	var max_y := region_cells[0].y
	for region_cell in region_cells:
		max_x = maxi(max_x, region_cell.x)
		max_y = maxi(max_y, region_cell.y)

	region_origin = Vector2i.ZERO
	grid_size = Vector2i(max_x + 1, max_y + 1)
	columns = maxi(grid_size.x, 1)
	for cell_y in range(grid_size.y):
		for cell_x in range(grid_size.x):
			var occupy_cell := Vector2i(cell_x, cell_y)
			var cell_patch: NinePatchRect
			if occupy_map.has_region_cell(occupy_cell):
				cell_patch = _create_region_cell_patch()
			else:
				cell_patch = _create_empty_cell_patch()
			cell_patch.custom_minimum_size = cell_size
			cell_panels.append(cell_patch)
			add_child(cell_patch)
			# 编辑器预览格子不写入场景，避免保存时污染 .tscn
			cell_patch.owner = null

## 创建合法区域底板格子。
func _create_region_cell_patch() -> NinePatchRect:
	var region_patch := NinePatchRect.new()
	region_patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	InventoryStyleBoxNinePatch.apply(region_patch, cell_style, show_cell_background)
	return region_patch

## 创建占位图边界内的空洞格子。
func _create_empty_cell_patch() -> NinePatchRect:
	var empty_patch := NinePatchRect.new()
	empty_patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	InventoryStyleBoxNinePatch.apply(empty_patch, empty_cell_style, show_cell_background)
	return empty_patch

## 重置网格状态（无占位图或占位图为空时使用）。
func _reset_grid_state() -> void:
	grid_size = Vector2i.ZERO
	region_origin = Vector2i.ZERO
	columns = 1

## 获取当前绑定的占位图资源。
func _get_occupy_map() -> OccupyMap:
	if inventory_data == null:
		return null
	return inventory_data.get_occupy_map()
#endregion

#region InventoryData 同步
## 连接 inventory_data 的占位图区域大小变化信号。
func _try_connect_inventory_data_signal() -> void:
	if !inventory_data:
		return
	if !inventory_data.occupy_map_changed.is_connected(sync_from_inventory_data):
		inventory_data.occupy_map_changed.connect(sync_from_inventory_data)


## 断开 inventory_data 的占位图区域大小变化信号。
func _try_disconnect_inventory_data_signal() -> void:
	if !inventory_data:
		return
	if inventory_data.occupy_map_changed.is_connected(sync_from_inventory_data):
		inventory_data.occupy_map_changed.disconnect(sync_from_inventory_data)

## 强制从 inventory_data 同步占位图与网格尺寸（引用未变时也可调用）。
func sync_from_inventory_data() -> void:
	if inventory_data == null:
		_clear_cell_panels()
		_reset_grid_state()
		updated.emit()
		return
	var inventory_occupy_map := inventory_data.get_occupy_map()
	if inventory_occupy_map:
		update_cell()
	else:
		_clear_cell_panels()
		_reset_grid_state()
		updated.emit()
#endregion

#region 获取
## 获取当前网格边界尺寸（由 OccupyMap 推导）。
func get_grid_dimensions() -> Vector2i:
	return grid_size

## 获取网格面板中的格子间距。
func get_cell_distance() -> Vector2i:
	return cell_spacing

## 获取单个格子的步进尺寸（格子大小 + 网格间距）。
func get_cell_step() -> Vector2:
	var cell_distance := get_cell_distance()
	return Vector2(cell_size.x + cell_distance.x, cell_size.y + cell_distance.y)

## 根据 OccupyMap 格子坐标获取其在面板局部空间中的左上角位置。
func get_cell_local_position(cell_index: Vector2i) -> Vector2:
	var step := get_cell_step()
	var local_cell_index := cell_index - region_origin
	return Vector2(step.x * local_cell_index.x, step.y * local_cell_index.y)

## 根据 OccupyMap 格子坐标获取其屏幕矩形（面板全局变换 + 格子尺寸）。
func get_cell_global_rect(cell_index: Vector2i) -> Rect2:
	return Rect2(get_global_transform() * get_cell_local_position(cell_index), cell_size)

## 根据面板局部坐标获取所在 OccupyMap 格子坐标；间隙、空洞或越界时返回 (-1, -1)。
func get_cell_by_local_position(local_position: Vector2) -> Vector2i:
	var step := get_cell_step()
	if step.x <= 0 or step.y <= 0 or grid_size == Vector2i.ZERO:
		return Vector2i(-1, -1)
	if local_position.x < 0.0 or local_position.y < 0.0:
		return Vector2i(-1, -1)
	var grid_index := Vector2i(int(local_position.x / step.x), int(local_position.y / step.y))
	if grid_index.x < 0 or grid_index.y < 0 or grid_index.x >= grid_size.x or grid_index.y >= grid_size.y:
		return Vector2i(-1, -1)
	var offset_in_step := Vector2(
		local_position.x - float(grid_index.x) * step.x,
		local_position.y - float(grid_index.y) * step.y
	)
	if offset_in_step.x >= cell_size.x or offset_in_step.y >= cell_size.y:
		return Vector2i(-1, -1)
	var cell_index := region_origin + grid_index
	if !has_cell(cell_index):
		return Vector2i(-1, -1)
	return cell_index

## 获取鼠标当前所在的格子坐标；
func get_mouse_cell() -> Vector2i:
	return get_cell_by_local_position(get_local_mouse_position())

## 获取当前网格总尺寸（格宽合计加中间间距，不含末尾多余间距）。
func get_grid_size() -> Vector2:
	if grid_size.x <= 0 or grid_size.y <= 0:
		return Vector2.ZERO
	var cell_distance := get_cell_distance()
	return Vector2(
		float(grid_size.x) * cell_size.x + float(grid_size.x - 1) * float(cell_distance.x),
		float(grid_size.y) * cell_size.y + float(grid_size.y - 1) * float(cell_distance.y)
	)

## 获取当前网格控件总数（含边界内空缺控件）。
func get_cell_num() -> int:
	return cell_panels.size()

## 获取当前占位图合法区域格子坐标列表。
func get_cells() -> Array[Vector2i]:
	var occupy_map := _get_occupy_map()
	if occupy_map == null:
		return []
	return occupy_map.get_region_cells()
#endregion

#region 判断
## 判断格子坐标是否为占位图合法区域。
func has_cell(cell_index: Vector2i) -> bool:
	var occupy_map := _get_occupy_map()
	if occupy_map == null:
		return false
	return occupy_map.has_region_cell(cell_index)

## 判断面板局部坐标是否落在有效格子中。
func is_local_position_in_cells(local_position: Vector2) -> bool:
	return get_cell_by_local_position(local_position) != Vector2i(-1, -1)

## 鼠标当前是否位于有效格子中。
func is_mouse_in_cells() -> bool:
	if !get_global_rect().has_point(get_global_mouse_position()):
		return false
	return get_mouse_cell() != Vector2i(-1, -1)
#endregion
