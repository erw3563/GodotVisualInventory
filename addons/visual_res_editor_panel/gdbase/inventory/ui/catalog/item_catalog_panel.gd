@tool
class_name ItemCatalogPanel
extends Control
## 物品目录面板：把 InventoryData 以「物品名 ×数量」的聚合列表形式展示。
## 同种物品（同 ItemData 且互为 is_same_item，即同轮廓阶段）聚合为一行，显示总数量；
## 行序由 sort_rule 预设规则派生，与占位无关——放置仅表示物品进入背包，不改变目录中的显示位置。
## 顶部容量条显示「占格 / 总格数」（满载判定口径；满员变警示色，自动扩容背包显示 ∞）。
## 指针事件统一由面板根节点接收并转发给 CatalogItemsInputController 处理。

## 目录行排序规则。
enum SortRule {
	NAME_ASC, ## 物品名升序（默认；名称并列时数量多者在前）。
	NAME_DESC, ## 物品名降序（名称并列时数量多者在前）。
	NUM_DESC, ## 数量降序（数量并列时物品名升序）。
}

## 一行的聚合数据：互为 is_same_item 的全部堆实例。
class CatalogItemGroup extends RefCounted:
	var instances: Array = []
	var item_data: ItemData
	var display_name := ""
	var icon: Texture2D

	var _cached_total_num := -1

	## 尝试把实例并入本组；空组直接收编，非空组要求与首实例互为同种。
	func try_add_instance(item_instance: ItemInstanceData) -> bool:
		if item_instance == null or item_instance.get_item_num() <= 0:
			return false
		if instances.is_empty():
			instances.append(item_instance)
			item_data = item_instance.get_item_data()
			display_name = item_instance.get_item_name()
			icon = item_instance.get_item_icon()
			_cached_total_num = -1
			return true
		if !instances[0].is_same_item(item_instance):
			return false
		instances.append(item_instance)
		_cached_total_num = -1
		return true

	## 组内总数量。
	func get_total_num() -> int:
		if _cached_total_num >= 0:
			return _cached_total_num
		var total := 0
		for item_instance in instances:
			if is_instance_valid(item_instance):
				total += item_instance.get_item_num()
		_cached_total_num = total
		return total

	## 取代表实例（首个），供悬停指向与中键开窗使用。
	func get_representative() -> ItemInstanceData:
		if instances.is_empty():
			return null
		return instances[0]

	## 取数量最多的一堆，供整组拿起使用。
	func get_largest_instance() -> ItemInstanceData:
		return _get_instance_by_num(true)

	## 取数量最少的一堆，供单个拿起使用（减少堆碎片）。
	func get_smallest_instance() -> ItemInstanceData:
		return _get_instance_by_num(false)

	func _get_instance_by_num(pick_largest: bool) -> ItemInstanceData:
		var picked: ItemInstanceData = null
		for item_instance in instances:
			if !is_instance_valid(item_instance) or item_instance.get_item_num() <= 0:
				continue
			if picked == null:
				picked = item_instance
				continue
			if pick_largest and item_instance.get_item_num() > picked.get_item_num():
				picked = item_instance
			if !pick_largest and item_instance.get_item_num() < picked.get_item_num():
				picked = item_instance
		return picked

	## 丢弃失效引用并按数量降序排列（整组拿起时先取大堆）。
	func collect_valid_instances_sorted_by_num_desc() -> Array:
		var valid_instances: Array = []
		for item_instance in instances:
			if is_instance_valid(item_instance) and item_instance.get_item_num() > 0:
				valid_instances.append(item_instance)
		valid_instances.sort_custom(func(a, b): return a.get_item_num() > b.get_item_num())
		return valid_instances


## 背包数据（标准 InventoryData，无目录专属数据类）。
@export var inventory_data: InventoryData:
	set(value):
		_try_disconnect_inventory_data_signal()
		inventory_data = value
		if !is_node_ready():
			await ready
		_apply_inventory_data_binding()

## 行排序规则（预设规律的默认值，可按面板覆盖）。
@export var sort_rule: SortRule = SortRule.NAME_ASC:
	set(value):
		if sort_rule == value:
			return
		sort_rule = value
		rebuild_rows()

## 是否在行首显示物品图标。
@export var show_icon := true:
	set(value):
		if show_icon == value:
			return
		show_icon = value
		rebuild_rows()

## 行 PanelContainer 的 panel StyleBox；空值回退内建样式。
@export var row_style: StyleBox:
	set(value):
		if row_style == value:
			return
		row_style = value
		rebuild_rows()

## 悬停行 StyleBox；空值回退内建悬停样式。
@export var row_hover_style: StyleBox:
	set(value):
		if row_hover_style == value:
			return
		row_hover_style = value
		rebuild_rows()

## 赋给行 PanelContainer 的 Material（含 ShaderMaterial）；空值不赋材质。
@export var row_material: Material:
	set(value):
		if row_material == value:
			return
		row_material = value
		rebuild_rows()

## 行内物品图标 modulate。
@export var icon_modulate := Color.WHITE:
	set(value):
		if icon_modulate == value:
			return
		icon_modulate = value
		rebuild_rows()

## 名称 Label 字体色。
@export var name_font_color := Color.WHITE:
	set(value):
		if name_font_color == value:
			return
		name_font_color = value
		rebuild_rows()

## 名称字号；0 表示不覆盖主题。
@export_range(0, 128, 1, "or_greater") var name_font_size := 0:
	set(value):
		var clamped := maxi(0, value)
		if name_font_size == clamped:
			return
		name_font_size = clamped
		rebuild_rows()

## 数量 Label 字体色。
@export var count_font_color := Color(0.92, 0.86, 0.6, 1.0):
	set(value):
		if count_font_color == value:
			return
		count_font_color = value
		rebuild_rows()

## 数量字号；0 表示不覆盖主题。
@export_range(0, 128, 1, "or_greater") var count_font_size := 0:
	set(value):
		var clamped := maxi(0, value)
		if count_font_size == clamped:
			return
		count_font_size = clamped
		rebuild_rows()

## 名称过滤关键字（大小写不敏感包含匹配）；空串不过滤。无限物品面板搜索框驱动。
var name_filter := "":
	set(value):
		if name_filter == value:
			return
		name_filter = value
		rebuild_rows()

## 每排高度（像素）；同时约束行内图标约 (高度 - 10)。
@export var row_height := 32:
	set(value):
		row_height = maxi(16, value)
		rebuild_rows()

## 拿取时物品图标尺寸；供手持预览使用，不控制目录排高。
@export var cell_size := Vector2(48, 48)
## 目录面板最小尺寸：宽度为最小宽；高度为内容高度下限。
@export var min_panel_size := Vector2(216.0, 96.0)
## 面板最大高度（超出后内部滚动）。
@export var max_panel_height := 360.0

## 是否在面板顶部显示容量条（「占格 / 总格数」）；未绑定背包数据时不显示。
@export var show_capacity_header := true:
	set(value):
		if show_capacity_header == value:
			return
		show_capacity_header = value
		_update_capacity_header()
		_update_preferred_size()

## 容量条平时配色（与行内数量标签默认色一致）。
const CAPACITY_NORMAL_COLOR := Color(0.92, 0.86, 0.6)
## 容量条满员警示配色。
const CAPACITY_FULL_COLOR := Color(1.0, 0.45, 0.35)

## 绑定的输入控制器。
var _items_input_controller: CatalogItemsInputController
## 排序后的聚合组（与 _rows 同序）。
var _groups: Array = []
## 行控件列表。
var _rows: Array = []
var _row_icons: Array[ItemIconView] = []
var _view_provider: InventoryItemViewProvider
var _content_box: VBoxContainer
var _capacity_header: Label
var _scroll_container: ScrollContainer
var _rows_box: VBoxContainer
var _empty_hint: Label
var _row_stylebox: StyleBoxFlat
var _row_hover_stylebox: StyleBoxFlat
var _hovered_row_index := -1
## 已连接 num_changed 的实例（重建时统一断开）。
var _num_signal_instances: Array[ItemInstanceData] = []
var _applying_configuration := false


## 在首次挂载前或一次刷新中批量下发配置，只重建一次。
func apply_configuration(configuration: Dictionary) -> void:
	_applying_configuration = true
	for key in configuration:
		set(key, configuration[key])
	_applying_configuration = false
	rebuild_rows()


func _ready() -> void:
	_ensure_ui_nodes()
	mouse_filter = Control.MOUSE_FILTER_STOP
	if !gui_input.is_connected(_on_gui_input):
		gui_input.connect(_on_gui_input)
	if !mouse_entered.is_connected(_on_pointer_entered):
		mouse_entered.connect(_on_pointer_entered)
	if !mouse_exited.is_connected(_on_pointer_exited):
		mouse_exited.connect(_on_pointer_exited)
	_apply_inventory_data_binding()


#region 数据绑定与刷新

## 设置背包数据并刷新显示。
func set_inventory_data(inventory_data_: InventoryData) -> void:
	inventory_data = inventory_data_


## 连接背包信号并全量重建。
func _apply_inventory_data_binding() -> void:
	_try_connect_inventory_data_signal()
	rebuild_rows()


## 强制刷新全部行（数据引用未变时也可调用）。
func refresh_display() -> void:
	rebuild_rows()


## 清空并按当前数据重建全部行。
func rebuild_rows() -> void:
	if !is_node_ready() or _applying_configuration:
		return
	_collect_groups()
	_sync_instance_num_signals()
	_clear_rows()
	for group in _groups:
		var row := _create_row(group)
		_rows_box.add_child(row)
		_rows.append(row)
	if _empty_hint:
		_empty_hint.visible = _groups.is_empty()
	_hovered_row_index = -1
	_update_capacity_header()
	_update_preferred_size()


## 收集并按 sort_rule 排序聚合组。
func _collect_groups() -> void:
	_groups.clear()
	if inventory_data == null:
		return
	for item_instance in inventory_data.get_item_instances():
		if item_instance == null or item_instance.get_item_num() <= 0:
			continue
		var merged := false
		for group in _groups:
			if group.try_add_instance(item_instance):
				merged = true
				break
		if !merged:
			var group := CatalogItemGroup.new()
			group.try_add_instance(item_instance)
			_groups.append(group)
	_finalize_collected_groups()


## 排序并应用名称过滤；子类自行填充 _groups 后调用。
func _finalize_collected_groups() -> void:
	_groups.sort_custom(_compare_groups)
	if !name_filter.is_empty():
		var keyword := name_filter.to_lower()
		_groups = _groups.filter(
			func(group): return group.display_name.to_lower().contains(keyword)
		)


## 排序比较器：a 应排在 b 前时返回 true。
func _compare_groups(a, b) -> bool:
	var order: int = a.display_name.casecmp_to(b.display_name)
	match sort_rule:
		SortRule.NAME_DESC:
			if order != 0:
				return order == 1
			return a.get_total_num() > b.get_total_num()
		SortRule.NUM_DESC:
			if a.get_total_num() != b.get_total_num():
				return a.get_total_num() > b.get_total_num()
			return order == -1
		_:
			if order != 0:
				return order == -1
			return a.get_total_num() > b.get_total_num()


func _clear_rows() -> void:
	for row in _rows:
		if is_instance_valid(row):
			row.queue_free()
	_rows.clear()
	_row_icons.clear()


## 把行内实例的 num_changed 连接到统一刷新（先断开旧连接）。
func _sync_instance_num_signals() -> void:
	for item_instance in _num_signal_instances:
		if is_instance_valid(item_instance) and item_instance.num_changed.is_connected(_on_instance_num_changed):
			item_instance.num_changed.disconnect(_on_instance_num_changed)
	_num_signal_instances.clear()
	for group in _groups:
		for item_instance in group.instances:
			if !is_instance_valid(item_instance):
				continue
			if !item_instance.num_changed.is_connected(_on_instance_num_changed):
				item_instance.num_changed.connect(_on_instance_num_changed)
			_num_signal_instances.append(item_instance)

#endregion


#region 容量显示

## 刷新容量条文本与满员配色；库存信号均已汇入 rebuild_rows，随重建自动刷新。
func _update_capacity_header() -> void:
	if _capacity_header == null or !is_instance_valid(_capacity_header):
		return
	var occupy_map := _get_occupy_map_for_capacity()
	if occupy_map == null:
		_capacity_header.visible = false
		return
	var occupied_cell_num := occupy_map.occupied_cells.size()
	var total_cell_num := occupy_map.cells.size()
	_capacity_header.text = _format_capacity_text(
		occupied_cell_num, total_cell_num, occupy_map.is_auto_expand
	)
	_capacity_header.visible = true
	var is_capacity_full: bool = (
		!occupy_map.is_auto_expand
		and total_cell_num > 0
		and occupied_cell_num >= total_cell_num
	)
	_capacity_header.modulate = CAPACITY_FULL_COLOR if is_capacity_full else CAPACITY_NORMAL_COLOR


## 取容量统计来源占位图；开关关闭或未绑定数据时返回 null。
func _get_occupy_map_for_capacity() -> OccupyMap:
	if !show_capacity_header or inventory_data == null:
		return null
	return inventory_data.occupy_map


## 容量条文本；子类可覆写（自定义前缀或无限符号写法）。
func _format_capacity_text(occupied_cell_num: int, total_cell_num: int, is_limitless: bool) -> String:
	if is_limitless:
		return "占用 %d / ∞" % occupied_cell_num
	return "占用 %d / %d" % [occupied_cell_num, total_cell_num]

#endregion


#region 库存数据信号

func _try_connect_inventory_data_signal() -> void:
	if inventory_data == null:
		return
	_set_inventory_data_signals(true)

func _try_disconnect_inventory_data_signal() -> void:
	if inventory_data == null:
		return
	_set_inventory_data_signals(false)

## 目录展示只关心“内容变了”，全部信号粗粒度合并到全量重建。
func _set_inventory_data_signals(is_connect: bool) -> void:
	_set_signal_connection(inventory_data.item_added, _on_inventory_changed, is_connect)
	_set_signal_connection(inventory_data.item_removed, _on_inventory_changed, is_connect)
	_set_signal_connection(inventory_data.item_position_changed, _on_inventory_changed, is_connect)
	_set_signal_connection(inventory_data.item_corrected, _on_inventory_changed, is_connect)
	_set_signal_connection(inventory_data.item_rotated, _on_inventory_changed, is_connect)
	_set_signal_connection(inventory_data.item_reshaped, _on_inventory_changed, is_connect)
	_set_signal_connection(inventory_data.sorted, _on_inventory_changed, is_connect)
	_set_signal_connection(inventory_data.inventory_cleared, _on_inventory_changed, is_connect)
	_set_signal_connection(inventory_data.occupy_map_changed, _on_inventory_changed, is_connect)
	_set_signal_connection(inventory_data.item_cannot_be_handled, _on_inventory_changed, is_connect)

func _set_signal_connection(target_signal: Signal, target_callable: Callable, is_connect: bool) -> void:
	if is_connect:
		if !target_signal.is_connected(target_callable):
			target_signal.connect(target_callable)
	else:
		if target_signal.is_connected(target_callable):
			target_signal.disconnect(target_callable)

## 背包内容变化：全量重建（适配各现行信号的 0~2 个参数）。
func _on_inventory_changed(_arg1 = null, _arg2 = null) -> void:
	rebuild_rows()

## 行内实例数量变化：全量重建。
func _on_instance_num_changed(_num: int) -> void:
	rebuild_rows()

#endregion


#region 行构建与外观

func _ensure_ui_nodes() -> void:
	if _scroll_container != null and is_instance_valid(_scroll_container):
		return
	_content_box = VBoxContainer.new()
	_content_box.name = "ContentBox"
	_content_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content_box.add_theme_constant_override("separation", 2)
	add_child(_content_box)

	_capacity_header = Label.new()
	_capacity_header.name = "CapacityHeader"
	_capacity_header.text = ""
	_capacity_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_capacity_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_capacity_header.add_theme_font_size_override("font_size", 12)
	_capacity_header.modulate = CAPACITY_NORMAL_COLOR
	_capacity_header.visible = false
	_content_box.add_child(_capacity_header)

	_scroll_container = ScrollContainer.new()
	_scroll_container.name = "ScrollContainer"
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content_box.add_child(_scroll_container)

	_rows_box = VBoxContainer.new()
	_rows_box.name = "RowsBox"
	_rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 2)
	_scroll_container.add_child(_rows_box)

	_empty_hint = Label.new()
	_empty_hint.name = "EmptyHint"
	_empty_hint.text = "目录为空"
	_empty_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_hint.modulate = Color(1, 1, 1, 0.5)
	_empty_hint.visible = false
	add_child(_empty_hint)
	_empty_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER)

	_row_stylebox = StyleBoxFlat.new()
	_row_stylebox.bg_color = Color(0.08, 0.08, 0.1, 0.92)
	_row_stylebox.border_color = Color(0.35, 0.36, 0.4, 0.7)
	_row_stylebox.set_border_width_all(1)
	_row_stylebox.set_corner_radius_all(4)
	_row_stylebox.content_margin_left = 6.0
	_row_stylebox.content_margin_right = 6.0

	_row_hover_stylebox = _row_stylebox.duplicate() as StyleBoxFlat
	_row_hover_stylebox.bg_color = Color(0.22, 0.24, 0.3, 0.95)
	_row_hover_stylebox.border_color = Color(0.55, 0.57, 0.64, 0.9)


## 解析当前应使用的行 StyleBox；配置为空时回退内建样式。
func _resolve_row_style(hovered: bool) -> StyleBox:
	_ensure_ui_nodes()
	if hovered:
		return row_hover_style if row_hover_style != null else _row_hover_stylebox
	return row_style if row_style != null else _row_stylebox


## 构建单行：[图标] 物品名 …… ×数量。
func _create_row(group: CatalogItemGroup) -> PanelContainer:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(0.0, row_height)
	row.add_theme_stylebox_override("panel", _resolve_row_style(false))
	row.material = row_material

	var content := HBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	content.add_theme_constant_override("separation", 6)
	row.add_child(content)

	if show_icon:
		var icon_rect := ItemIconView.new()
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_rect.custom_minimum_size = Vector2(row_height - 10.0, row_height - 10.0)
		icon_rect.modulate = icon_modulate
		icon_rect.bind_item(group.get_representative())
		icon_rect.set_base_texture(group.icon)
		icon_rect.set_sync_callback(_sync_item_view)
		_row_icons.append(icon_rect)
		content.add_child(icon_rect)

	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.text = group.display_name
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_color_override("font_color", name_font_color)
	if name_font_size > 0:
		name_label.add_theme_font_size_override("font_size", name_font_size)
	content.add_child(name_label)

	var num_label := Label.new()
	num_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	num_label.text = _format_group_count(group)
	num_label.visible = not num_label.text.is_empty()
	num_label.add_theme_color_override("font_color", count_font_color)
	if count_font_size > 0:
		num_label.add_theme_font_size_override("font_size", count_font_size)
	content.add_child(num_label)
	return row


## 行尾数量文本；模板目录返回空文本，不暗示库存数量。
func _format_group_count(group) -> String:
	return "×%d" % group.get_total_num()


## 按行数更新面板最小尺寸（供宿主同步）；容量条可见时计入其高度。
func _update_preferred_size() -> void:
	var header_height := 0.0
	if _capacity_header != null and is_instance_valid(_capacity_header) and _capacity_header.visible:
		header_height = _capacity_header.get_combined_minimum_size().y + 2.0
	var content_height := float(_rows.size()) * (row_height + 2.0) + 8.0 + header_height
	var preferred_height := clampf(content_height, min_panel_size.y, max_panel_height)
	custom_minimum_size = Vector2(min_panel_size.x, preferred_height)

#endregion


#region 指针交互

## 绑定目录输入控制器（面板统一接收 gui_input 后转发）。
func bind_items_input_controller(controller: CatalogItemsInputController) -> void:
	if _items_input_controller == controller:
		return
	_items_input_controller = controller
	if is_instance_valid(_items_input_controller) and _items_input_controller.catalog_panel == null:
		_items_input_controller.set("catalog_panel", self)


func _on_gui_input(event: InputEvent) -> void:
	if !is_instance_valid(_items_input_controller):
		return
	_items_input_controller.activate_input()
	if event is InputEventMouseMotion:
		_update_hovered_row()
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


## 鼠标是否在面板区域内。
func is_mouse_in_panel() -> bool:
	return get_global_rect().has_point(get_global_mouse_position())


## 鼠标所在行对应的聚合组；不在任何行上时返回 null。
func get_item_group_under_mouse():
	var row_index := _find_row_index_under_mouse()
	if row_index < 0:
		return null
	return _groups[row_index]


func _find_row_index_under_mouse() -> int:
	var mouse_position := get_global_mouse_position()
	for index in _rows.size():
		var row: Control = _rows[index]
		if is_instance_valid(row) and row.get_global_rect().has_point(mouse_position):
			return index
	return -1


## 刷新悬停行高亮。
func _update_hovered_row() -> void:
	var new_index := _find_row_index_under_mouse()
	if new_index == _hovered_row_index:
		return
	_apply_row_style(_hovered_row_index, false)
	_hovered_row_index = new_index
	_apply_row_style(_hovered_row_index, true)

func _apply_row_style(row_index: int, hovered: bool) -> void:
	if row_index < 0 or row_index >= _rows.size():
		return
	var row: Control = _rows[row_index]
	if !is_instance_valid(row):
		return
	row.add_theme_stylebox_override("panel", _resolve_row_style(hovered))

#endregion


#region 查询接口

## 当前展示的聚合组（显示顺序）。
func get_catalog_groups() -> Array:
	return _groups.duplicate()

## 当前行数。
func get_row_count() -> int:
	return _rows.size()

## 指定索引的行 PanelContainer；越界返回 null。
func get_row_at(row_index: int) -> PanelContainer:
	if row_index < 0 or row_index >= _rows.size():
		return null
	var row: Control = _rows[row_index]
	return row as PanelContainer if is_instance_valid(row) else null

## 各行显示文本（"物品名×数量"，按显示顺序），供测试断言。
func get_group_texts() -> PackedStringArray:
	var texts := PackedStringArray()
	for group in _groups:
		texts.append("%s%s" % [group.display_name, _format_group_count(group)])
	return texts

## 设置名称过滤关键字（空串清除过滤）。
func set_name_filter(filter_text: String) -> void:
	name_filter = filter_text

## 拿取时物品图标尺寸。
func get_catalog_cell_size() -> Vector2:
	return cell_size

## 目录面板期望尺寸（供宿主同步最小尺寸）。
func get_catalog_preferred_size() -> Vector2:
	return custom_minimum_size if custom_minimum_size.x > 0.0 else min_panel_size

## 容量条当前文本（不可见时为空串），供测试断言。
func get_capacity_header_text() -> String:
	if !is_capacity_header_visible():
		return ""
	return _capacity_header.text

## 容量条是否可见。
func is_capacity_header_visible() -> bool:
	return (
		_capacity_header != null
		and is_instance_valid(_capacity_header)
		and _capacity_header.visible
	)

## 容量条是否处于满员警示态。
func is_capacity_header_marked_full() -> bool:
	return is_capacity_header_visible() and _capacity_header.modulate == CAPACITY_FULL_COLOR

#endregion


func set_view_provider(provider: InventoryItemViewProvider) -> void:
	_view_provider = provider
	for view in _row_icons:
		if is_instance_valid(view):
			view.set_sync_callback(_sync_item_view)

func _sync_item_view(item: ItemInstanceData, view: ItemIconView) -> void:
	if _view_provider != null:
		_view_provider.sync_view(item, view)

func get_item_views(item: ItemInstanceData) -> Array[ItemIconView]:
	if not show_icon:
		return []
	for index in mini(_groups.size(), _row_icons.size()):
		var view := _row_icons[index]
		if _groups[index].get_representative() == item and is_instance_valid(view) and not view.is_queued_for_deletion() and view.get_bound_item() == item:
			return [view]
	return []
