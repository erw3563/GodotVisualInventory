@tool
class_name InventoryShapeOverlay
extends Control
## 背包形状覆盖层。
## 该节点持有 InventoryData，并根据其中物品占据格子自动生成边框。
## 同时支持手持物品预览边框显示。

enum PreviewState {
	VALID,
	INVALID,
}

## 网格面板（用于格子坐标转像素坐标）。
@export var inventory_grid_panel: InventoryGridPanel
## 背包数据（用于自动生成已放置物品边框）。
@export var inventory_data: InventoryData:
	set(value):
		if inventory_data != value:
			_requests.clear()
			_mark_batches.clear()
			clear_preview()
		_try_disconnect_inventory_data_signal()
		inventory_data = value
		_try_connect_inventory_data_signal()
		_try_auto_rebuild_placed_item_borders()
## 覆盖层级：与物品图标格同级（1）；覆盖层与图标的先后由装配挂载顺序决定。
@export var overlay_z_index: int = 1
## 显式默认外观；只按同键兜底，空时不加载资源。
@export var default_cell_appearance_part: ItemCellAppearancePart
@export_group("Color")
## 回退边框线宽（样式未声明宽度时使用）。
@export var border_width: float = 3.0
## 无效操作反馈变色持续时间。
@export var invalid_click_feedback_time: float = 0.18
@export_group("显示开关")
## 是否渲染已放置物品的自身边框（常驻层）。
@export var show_placed_border := true:
	set(value):
		if show_placed_border == value:
			return
		show_placed_border = value
		_on_display_switch_changed()
## 是否渲染手持物品放置预览边框。
@export var show_place_preview := true:
	set(value):
		if show_place_preview == value:
			return
		show_place_preview = value
		_on_display_switch_changed()


## 当前预览占用的格子坐标列表。
var preview_cells: Array[Vector2i] = []
## 当前预览是否可放置。
var preview_state: PreviewState = PreviewState.VALID
## 已放置物品边框与填充的子容器。
var placed_item_container: Control:
	get:
		if !is_instance_valid(placed_item_container):
			placed_item_container = _create_shape_container("PlacedItemContainer")
		return placed_item_container
## 手持物品预览边框与填充的子容器。
var preview_container: Control:
	get:
		if !is_instance_valid(preview_container):
			preview_container = _create_shape_container("PreviewContainer")
		return preview_container
## 物品外部框填充子容器；画在已放置填充之下。
var cell_mark_fill_container: Control:
	get:
		if !is_instance_valid(cell_mark_fill_container):
			cell_mark_fill_container = _create_shape_container("CellMarkFillContainer")
			move_child(cell_mark_fill_container, 0)
		return cell_mark_fill_container
## 物品外部框描边子容器；画在已放置边框之上。
var cell_mark_border_container: Control:
	get:
		if !is_instance_valid(cell_mark_border_container):
			cell_mark_border_container = _create_shape_container("CellMarkBorderContainer")
		return cell_mark_border_container
var _requests: Dictionary = {}
var _mark_batches: Dictionary = {}
static var _next_handle: int = 1
var placed_renderers: Array[InventoryItemStyleRenderer] = []
var preview_renderers: Array[InventoryItemStyleRenderer] = []
var mark_renderers: Array[InventoryItemStyleRenderer] = []
## 视觉状态策略（负责颜色决策与无效反馈状态管理）。
var visual_state_strategy := InventoryShapeOverlayVisualState.new()

#region 生命周期
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = overlay_z_index
	_sync_render_strategy_config()
	_sync_layout_with_grid_panel()
	_try_auto_rebuild_placed_item_borders()


func _exit_tree() -> void:
	_clear_renderers(placed_renderers)
	_clear_renderers(preview_renderers)
	_clear_renderers(mark_renderers)
	_try_disconnect_inventory_data_signal()
	_requests.clear()
	_mark_batches.clear()

func _process(_delta: float) -> void:
	_sync_layout_with_grid_panel()

#endregion

## 返回 0 表示请求无效；句柄只属于当前覆盖层且永不复用。
func request_appearance(item: ItemInstanceData, id: StringName, priority: int = 0, exclude_fill: bool = false) -> int:
	if not _can_request(item, id):
		return 0
	var handle := _next_handle
	_next_handle += 1
	_requests[handle] = {"item": item, "id": id, "priority": priority, "exclude_fill": exclude_fill}
	refresh_placed_item_borders()
	return handle

func update_appearance(handle: int, id: StringName, priority: int = 0, exclude_fill: bool = false) -> bool:
	if not _requests.has(handle) or not _can_request(_requests[handle].item, id):
		return false
	_requests[handle].id = id
	_requests[handle].priority = priority
	_requests[handle].exclude_fill = exclude_fill
	refresh_placed_item_borders()
	return true

func release_appearance(handle: int) -> void:
	if _requests.erase(handle):
		refresh_placed_item_borders()

func _can_request(item: ItemInstanceData, id: StringName) -> bool:
	return inventory_data != null and item != null and inventory_data.get_item_instances().has(item) and resolve_appearance(item, id) != null

func resolve_appearance(item: ItemInstanceData, id: StringName) -> InventoryItemVisualStyle:
	return InventoryCellAppearancePartResolver.resolve_style(item, id, default_cell_appearance_part)

func _prune_requests() -> void:
	for handle in _requests.keys():
		if inventory_data == null or not inventory_data.get_item_instances().has(_requests[handle].item):
			_requests.erase(handle)

func _get_override_style(item: ItemInstanceData) -> InventoryItemVisualStyle:
	var winner: Dictionary = {}
	for request in _requests.values():
		if request.item == item and (winner.is_empty() or request.priority > winner.priority):
			winner = request
	return resolve_appearance(item, winner.id) if not winner.is_empty() else null

func create_mark_source() -> int:
	var handle := _next_handle
	_next_handle += 1
	_mark_batches[handle] = []
	return handle

## 每条记录包含 cells、item、id；验证整个批次后才替换。
func submit_marks(handle: int, records: Array[Dictionary]) -> bool:
	if not _mark_batches.has(handle) or inventory_data == null:
		return false
	var marks: Array[InventoryCellMark] = []
	for record in records:
		if not record.has_all(["cells", "item", "id"]):
			return false
		if not record.item is ItemInstanceData or not record.cells is Array or not (record.id is StringName or record.id is String):
			return false
		var style := resolve_appearance(record.item, record.id)
		if style == null:
			return false
		var cells: Array[Vector2i] = []
		for cell in record.cells:
			if not cell is Vector2i or not inventory_data.get_occupy_map().cells.has(cell):
				return false
			if not cells.has(cell):
				cells.append(cell)
		if not cells.is_empty():
			var mark := InventoryCellMark.new()
			mark.init_mark(cells, style)
			marks.append(mark)
	_mark_batches[handle] = marks
	_rebuild_cell_marks()
	return true

func clear_marks(handle: int) -> void:
	if _mark_batches.has(handle):
		_mark_batches[handle] = []
		_rebuild_cell_marks()

func release_mark_source(handle: int) -> void:
	if _mark_batches.erase(handle):
		_rebuild_cell_marks()

#region 对外接口
## 显示预览格子；格子、可放置状态与样式物品均未变化时跳过重建。
## style_item 为手持物品实例，用于解析放置预览与预览反馈的样式。
func set_preview_cells(
	cells: Array[Vector2i],
	is_valid: bool,
	style_item: ItemInstanceData = null
) -> void:
	var target_preview_state := PreviewState.VALID if is_valid else PreviewState.INVALID
	if preview_state == target_preview_state \
			and visual_state_strategy.preview_style_item == style_item \
			and _are_preview_cells_equal(preview_cells, cells):
		return
	preview_cells = cells.duplicate()
	preview_state = target_preview_state
	visual_state_strategy.preview_style_item = style_item
	visual_state_strategy.set_preview_state(is_valid)
	_rebuild_preview_borders()

## 清空当前预览显示。
func clear_preview() -> void:
	visual_state_strategy.preview_style_item = null
	if preview_cells.is_empty():
		return
	preview_state = PreviewState.VALID
	preview_cells.clear()
	if visual_state_strategy.invalid_feedback_is_preview:
		visual_state_strategy.clear_invalid_feedback_state()
	_clear_renderers(preview_renderers)
	queue_redraw()

## 主动刷新已放置物品边框。
func refresh_placed_item_borders() -> void:
	_rebuild_placed_item_borders()

## 播放无效操作反馈，目标框短暂变色。
## item_instance_data 为 null 时作用于预览框（如放置失败）；否则作用于该已放置物品框（如旋转失败）。
func play_invalid_action_feedback(item_instance_data: ItemInstanceData = null) -> void:
	var is_preview_feedback := item_instance_data == null
	if is_preview_feedback and preview_cells.is_empty():
		return
	var current_feedback_version := visual_state_strategy.start_invalid_feedback(item_instance_data)
	if is_preview_feedback:
		_rebuild_preview_borders()
	else:
		_rebuild_placed_item_borders()
	await get_tree().create_timer(invalid_click_feedback_time).timeout
	if not visual_state_strategy.is_feedback_version_valid(current_feedback_version):
		return
	visual_state_strategy.clear_invalid_feedback_state()
	if is_preview_feedback:
		_rebuild_preview_borders()
	else:
		_rebuild_placed_item_borders()
#endregion

#region 边框重建
## 重建已放置物品边框。
func _rebuild_placed_item_borders() -> void:
	_prune_requests()
	_clear_renderers(placed_renderers)
	_sync_render_strategy_config()
	if inventory_data == null:
		_rebuild_cell_marks()
		queue_redraw()
		return
	for item_instance_data in inventory_data.get_item_instances():
		if item_instance_data == null:
			continue
		var target_cells := inventory_data.get_occupy_map().get_cells_of_occupant(item_instance_data)
		if target_cells.is_empty():
			continue
		_build_shape_to_container(
			target_cells,
			placed_item_container,
			visual_state_strategy.get_placed_item_style(item_instance_data, _get_override_style(item_instance_data))
		)
	_rebuild_cell_marks()
	queue_redraw()

## 重建手持物品预览边框；预览开关关闭时仅清空不绘制。
func _rebuild_preview_borders() -> void:
	_clear_renderers(preview_renderers)
	_sync_render_strategy_config()
	if not show_place_preview:
		queue_redraw()
		return
	if preview_cells.is_empty():
		queue_redraw()
		return
	_build_shape_to_container(
		preview_cells,
		preview_container,
		visual_state_strategy.get_preview_style()
	)
	queue_redraw()

## 将一组形状格子按样式绘制到目标容器。
func _build_shape_to_container(
	target_cells: Array[Vector2i],
	target_container: Control,
	style: InventoryItemVisualStyle
) -> void:
	if !is_instance_valid(inventory_grid_panel) or style == null:
		return
	var renderers := preview_renderers if target_container == preview_container else placed_renderers
	_create_renderer(style, target_cells, target_cells, target_container, target_container, renderers)

func _create_renderer(style: InventoryItemVisualStyle, borders: Array[Vector2i], fills: Array[Vector2i], border_parent: Control, fill_parent: Control, renderers: Array[InventoryItemStyleRenderer]) -> void:
	if style == null or not style.validate_configuration().is_empty():
		return
	var binding := InventoryItemStyleRenderContext.new()
	binding.grid = inventory_grid_panel
	binding.default_border_width = border_width
	binding.border_parent = border_parent
	binding.fill_parent = fill_parent
	var renderer := style.create_renderer()
	if renderer == null:
		return
	add_child(renderer)
	if not renderer.configure(style, binding):
		remove_child(renderer)
		renderer.queue_free()
		return
	renderer.render(borders, fills)
	renderers.append(renderer)

func _clear_renderers(renderers: Array[InventoryItemStyleRenderer]) -> void:
	for renderer in renderers:
		if is_instance_valid(renderer):
			renderer.release()
			if renderer.get_parent() != null:
				renderer.get_parent().remove_child(renderer)
			renderer.queue_free()
	renderers.clear()

#endregion

#region 物品外部框
func _rebuild_cell_marks() -> void:
	_clear_renderers(mark_renderers)
	for batch in _mark_batches.values():
		for mark in batch:
			_build_cell_mark(mark)
	queue_redraw()

## 渲染单条物品外部框：按通道拆分描边格与填充格并分层绘制。
## 描边层在已放置边框之上，填充层在已放置填充之下；
## 请求声明 exclude_fill 的占格跳过外部标记填充。
func _build_cell_mark(cell_mark: InventoryCellMark) -> void:
	if cell_mark == null or cell_mark.is_empty():
		return
	var border_cells: Array[Vector2i] = []
	if cell_mark.style.use_border:
		border_cells = cell_mark.cells
	var fill_cells := _collect_mark_fill_cells(cell_mark)
	if border_cells.is_empty() and fill_cells.is_empty():
		return
	_create_renderer(cell_mark.style, border_cells, fill_cells, cell_mark_border_container, cell_mark_fill_container, mark_renderers)

## 收集标记中参与填充的格子。
func _collect_mark_fill_cells(cell_mark: InventoryCellMark) -> Array[Vector2i]:
	var fill_cells: Array[Vector2i] = []
	if !cell_mark.style.use_fill:
		return fill_cells
	for cell in cell_mark.cells:
		if _is_cell_fill_excluded(cell):
			continue
		if !fill_cells.has(cell):
			fill_cells.append(cell)
	return fill_cells

func _is_cell_fill_excluded(cell: Vector2i) -> bool:
	if inventory_data == null:
		return false
	for request in _requests.values():
		if request.exclude_fill and inventory_data.get_occupy_map().get_cells_of_occupant(request.item).has(cell):
			return true
	return false

#endregion

#region InventoryData 信号
## 连接 InventoryData 相关信号。
func _try_connect_inventory_data_signal() -> void:
	if inventory_data:
		set_connection_inventory_data_signal(true)

## 断开 InventoryData 相关信号。
func _try_disconnect_inventory_data_signal() -> void:
	if inventory_data:
		set_connection_inventory_data_signal(false)

func set_connection_inventory_data_signal(ensure:bool):
	_set_signal_connection(inventory_data.item_added, _on_inventory_item_changed, ensure)
	_set_signal_connection(inventory_data.item_removed, _on_inventory_item_changed, ensure)
	_set_signal_connection(inventory_data.item_position_changed, _on_inventory_item_changed, ensure)
	_set_signal_connection(inventory_data.item_corrected, _on_inventory_item_changed, ensure)
	_set_signal_connection(inventory_data.item_rotated, _on_inventory_item_changed, ensure)
	_set_signal_connection(inventory_data.item_reshaped, _on_inventory_item_changed, ensure)
	_set_signal_connection(inventory_data.item_cannot_be_handled, _on_inventory_item_changed, ensure)
	_set_signal_connection(inventory_data.sorted, _on_inventory_items_changed, ensure)
	_set_signal_connection(inventory_data.inventory_cleared, _on_inventory_cleared, ensure)
	_set_signal_connection(inventory_data.occupy_map_changed, _on_inventory_items_changed, ensure)


## 统一管理信号连接状态。
func _set_signal_connection(target_signal: Signal, target_callable: Callable, is_connect: bool) -> void:
	if is_connect:
		if !target_signal.is_connected(target_callable):
			target_signal.connect(target_callable)
	else:
		if target_signal.is_connected(target_callable):
			target_signal.disconnect(target_callable)

## 物品增删时重建边框（参数仅用于匹配各信号签名，不使用）。
func _on_inventory_item_changed(
		_item_instance_data: ItemInstanceData = null,
		_previous_cell: Vector2i = Vector2i.ZERO
) -> void:
	_try_auto_rebuild_placed_item_borders()

## 物品状态变化时重建边框。
func _on_inventory_items_changed() -> void:
	_try_auto_rebuild_placed_item_borders()

## 背包清空时清理边框。
func _on_inventory_cleared() -> void:
	_requests.clear()
	_clear_renderers(placed_renderers)
	_rebuild_cell_marks()
	queue_redraw()
#endregion

#region 已放置边框同步策略

## 在允许自动同步时才重建已放置物品边框。
func _try_auto_rebuild_placed_item_borders() -> void:
	_rebuild_placed_item_borders()
#endregion

#region 布局与容器
## 判断两组预览格子坐标是否完全一致。
func _are_preview_cells_equal(cells_a: Array[Vector2i], cells_b: Array[Vector2i]) -> bool:
	if cells_a.size() != cells_b.size():
		return false
	for cell_index in range(cells_a.size()):
		if cells_a[cell_index] != cells_b[cell_index]:
			return false
	return true

## 根据网格面板同步覆盖层尺寸与位置。
func _sync_layout_with_grid_panel() -> void:
	if !is_instance_valid(inventory_grid_panel):
		visible = false
		return
	visible = true
	position = inventory_grid_panel.position
	size = inventory_grid_panel.get_grid_size()

## 创建形状覆盖子容器。
func _create_shape_container(container_name: String) -> Control:
	var container := Control.new()
	container.name = container_name
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.offset_left = 0.0
	container.offset_top = 0.0
	container.offset_right = 0.0
	container.offset_bottom = 0.0
	add_child(container)
	# 所有样式共用确定的视觉层序。
	for layer_name in ["CellMarkFillContainer", "PlacedItemContainer", "CellMarkBorderContainer", "PreviewContainer"]:
		var layer := get_node_or_null(NodePath(layer_name))
		if layer != null:
			move_child(layer, -1)
	return container

## 显示开关变更时刷新各层边框显示。
func _on_display_switch_changed() -> void:
	if !is_node_ready():
		return
	_try_auto_rebuild_placed_item_borders()
	if !preview_cells.is_empty():
		_rebuild_preview_borders()
	else:
		queue_redraw()

## 同步渲染策略所需配置。
func _sync_render_strategy_config() -> void:
	visual_state_strategy.sync_config(
		default_cell_appearance_part,
		show_placed_border
	)
#endregion
