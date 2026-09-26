@tool
class_name FreeItemCell
extends Control
## 自由格物品显示格：FREE 模式的基础显示单位，每个物品实例（堆）对应一格。
## 仅负责渲染（边框 / 图标 / 数量）与跟随物品实例信号刷新；不处理输入、不管位置——
## 输入统一由 FreeItemsPanel 的 gui_input 转发，位置由面板兜底流式排布或外部 UI 收养后接管。
## 底板外观由面板下发的 StyleBox 经 NinePatchRect 绘制。

signal cell_freed

## 悬停高亮提亮（叠加在边框 self_modulate 上）。
const HOVER_SELF_MODULATE := Color(1.5, 1.5, 1.5, 1.0)

var item_instance_data: ItemInstanceData
## 单元格尺寸（一格的像素大小）。
var unit_size: Vector2 = Vector2(48, 48)
## 是否跟随物品形状包围盒放大（形状背包为 true，非形状背包恒 1×1）。
var follow_shape := true
## 底板样式；空值表示透明底板。
var cell_style: StyleBox = null
## 是否绘制底板。
var show_cell_background := true

var _background: NinePatchRect
var icon_view: ItemIconView
var _count_label: Label


func _ready() -> void:
	_ensure_ui_nodes()
	refresh_display()


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		refresh_display()


func get_item_instance_data() -> ItemInstanceData:
	return item_instance_data


## 初始化格子显示并连接物品实例信号。
func init_item(
	item_instance_data_: ItemInstanceData,
	unit_size_: Vector2,
	follow_shape_: bool
) -> void:
	_ensure_ui_nodes()
	_disconnect_item_signals()
	item_instance_data = item_instance_data_
	unit_size = unit_size_
	follow_shape = follow_shape_
	if !item_instance_data.num_changed.is_connected(update_item_num_label):
		item_instance_data.num_changed.connect(update_item_num_label)
	if !item_instance_data.dir_changed.is_connected(update_item_rotate):
		item_instance_data.dir_changed.connect(update_item_rotate)
	if !item_instance_data.shape_changed.is_connected(refresh_display):
		item_instance_data.shape_changed.connect(refresh_display)
	refresh_display()


## 下发底板样式并立即应用到九宫格边框。
func configure_background(next_cell_style: StyleBox, next_show_cell_background: bool) -> void:
	cell_style = next_cell_style
	show_cell_background = next_show_cell_background
	_ensure_ui_nodes()
	_apply_background_style()


## 按物品实例当前状态刷新格子（尺寸 / 图标 / 数量 / 朝向）。
func refresh_display() -> void:
	if item_instance_data == null:
		return
	_ensure_ui_nodes()
	_apply_background_style()
	icon_view.bind_item(item_instance_data)
	icon_view.set_base_texture(item_instance_data.get_item_icon())
	update_item_rotate(item_instance_data.dir)
	update_item_num_label(item_instance_data.num)


## 当前显示尺寸：形状背包使用朝向变换后的像素包围盒，非形状背包恒一格。
func get_display_size() -> Vector2:
	if !follow_shape:
		return unit_size
	var shape_size := item_instance_data.get_shape_size()
	var base_size := Vector2(shape_size) * unit_size
	var quarter_turns := ShapeTransform.dir_to_rotate_num(item_instance_data.dir)
	return Vector2(base_size.y, base_size.x) if quarter_turns % 2 != 0 else base_size


func update_item_num_label(num: int) -> void:
	_count_label.text = str(num)
	_count_label.visible = num > 1
	if num == 0:
		cell_freed.emit()
		queue_free()


func update_item_rotate(direction: Vector2) -> void:
	if !is_instance_valid(icon_view):
		return
	var display_size := get_display_size()
	custom_minimum_size = display_size
	size = display_size
	var angle := ShapeTransform.dir_to_rotation_angle(direction)
	# 根格子保持布局朝向和旋转后命中范围；图标与边框在格心一起表达物品朝向。
	# 非形状背包保持固定格，先反算未旋转尺寸，避免矩形单位格旋转后溢出。
	var quarter_turns := ShapeTransform.dir_to_rotate_num(direction)
	var content_size := Vector2(display_size.y, display_size.x) if quarter_turns % 2 != 0 else display_size
	for visual: Control in [_background, icon_view]:
		visual.size = content_size
		visual.pivot_offset = content_size * 0.5
		visual.position = (display_size - content_size) * 0.5
		visual.rotation = angle


func set_highlighted(highlighted: bool) -> void:
	if is_instance_valid(_background):
		_background.self_modulate = HOVER_SELF_MODULATE if highlighted else Color.WHITE


## 确保 UI 节点存在，支持纯代码创建。
func _ensure_ui_nodes() -> void:
	if is_instance_valid(_background) and is_instance_valid(icon_view) and is_instance_valid(_count_label):
		return
	z_index = 1
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if !is_instance_valid(_background):
		_background = get_node_or_null("Background") as NinePatchRect
		if !is_instance_valid(_background):
			_background = _create_background()
			add_child(_background)
	if !is_instance_valid(icon_view):
		icon_view = get_node_or_null("IconView") as ItemIconView
		if !is_instance_valid(icon_view):
			icon_view = _createicon_view()
			add_child(icon_view)
	if !is_instance_valid(_count_label):
		_count_label = get_node_or_null("CountLabel") as Label
		if !is_instance_valid(_count_label):
			_count_label = _create_count_label()
			add_child(_count_label)


## 创建透明九宫格边框节点，贴图由 StyleBox 配置写入。
func _create_background() -> NinePatchRect:
	var background := NinePatchRect.new()
	background.name = "Background"
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	InventoryStyleBoxNinePatch.apply(background, cell_style, show_cell_background)
	return background


## 将当前底板样式应用到边框节点。
func _apply_background_style() -> void:
	if not is_instance_valid(_background):
		return
	InventoryStyleBoxNinePatch.apply(_background, cell_style, show_cell_background)


func _createicon_view() -> ItemIconView:
	var icon_rect := ItemIconView.new()
	icon_rect.name = "IconView"
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_rect.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	return icon_rect


func _create_count_label() -> Label:
	var count_label := Label.new()
	count_label.name = "CountLabel"
	count_label.modulate = Color(0.94, 0, 0, 1)
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	count_label.offset_left = -30.0
	count_label.offset_top = -18.0
	count_label.offset_right = -4.0
	count_label.offset_bottom = -2.0
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	count_label.label_settings = LabelSettings.new()
	return count_label


func _disconnect_item_signals() -> void:
	if item_instance_data == null:
		return
	for pair in [[item_instance_data.num_changed, update_item_num_label], [item_instance_data.dir_changed, update_item_rotate], [item_instance_data.shape_changed, refresh_display]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])
