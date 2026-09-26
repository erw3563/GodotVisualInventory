@tool
class_name InventoryItemBox
extends Control
## 背包物品显示框；@tool 以便编辑器中的 @tool 面板可调用 init_cell 等自定义方法。

signal item_box_freed

@export var icon_view: ItemIconView
@export var label: Label

var item_instance_data: ItemInstanceData
var center_pos: Vector2
var invalid_placement_feedback_tween: Tween
var feedback_tween: Tween
var _panel_container: PanelContainer
var _item_texture_size: Vector2 = Vector2.ZERO
var _item_box_size: Vector2 = Vector2.ZERO
var _display_snapshot: Dictionary = {}
var _is_icon_display_delayed := false
var _icon_delay_tween: Tween
var _icon_display_holds: Dictionary = {}
var _next_icon_display_hold := 0

func _ready() -> void:
	_ensure_ui_nodes()
	refresh_display()


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		refresh_display()


func get_center() -> Vector2:
	return center_pos


func get_item_instance_data() -> ItemInstanceData:
	return item_instance_data

## 初始化物品格子显示。
func init_cell(item_instance_data_: ItemInstanceData, item_texture_size: Vector2, item_box_size: Vector2) -> void:
	_ensure_ui_nodes()
	_disconnect_item_signals()
	_display_snapshot.clear()
	item_instance_data = item_instance_data_
	icon_view.bind_item(item_instance_data)
	item_instance_data.num_changed.connect(update_item_num_label)
	item_instance_data.dir_changed.connect(update_item_rotate)
	if !item_instance_data.shape_changed.is_connected(refresh_display):
		item_instance_data.shape_changed.connect(refresh_display)
	_item_texture_size = item_texture_size
	_item_box_size = item_box_size
	refresh_display()

## 根据当前物品数据刷新格子显示。
func refresh_display() -> void:
	if item_instance_data == null:
		return
	_ensure_ui_nodes()
	_refresh_display_layout()
	update_item_num_label(item_instance_data.num)


## 以快照初始化纯展示幽灵格（物品动画用）：不连接物品信号、不随数量归零自毁。
## display_num 用调用方提供的转移前快照——物品实例可能已被合并吸收（num 归零），
## 直接读实时数量会触发自毁路径；图标/形状/朝向取当前值（转移不改变这些字段）。
func init_cell_snapshot(
	item_instance_data_: ItemInstanceData,
	item_texture_size: Vector2,
	item_box_size: Vector2,
	display_num: int,
	display_snapshot: Dictionary = {}
) -> void:
	_ensure_ui_nodes()
	item_instance_data = item_instance_data_
	_item_texture_size = item_texture_size
	_item_box_size = item_box_size
	_display_snapshot = display_snapshot.duplicate()
	_refresh_display_layout()
	icon_view.bind_item(null)
	icon_view.set_base_texture(_display_snapshot.get("texture", item_instance_data.get_item_icon()))
	label.text = str(display_num)
	label.visible = display_num > 1


## 按当前物品数据刷新布局、图标与朝向（不含数量标签——快照幽灵须自行覆盖数量）。
func _refresh_display_layout() -> void:
	icon_view.set_base_texture(item_instance_data.get_item_icon())
	update_item_rotate(_display_snapshot.get("dir", item_instance_data.dir))

## 刷新盒子与面板几何（随朝向变化）：盒子覆盖旋转后的占格包围盒，图标面板预旋转覆盖
## 未旋转包围盒、绕 (0,0) 锚点格中心旋转后恰好铺满盒子——物品中心（get_center）
## 即占格包围盒中心，不再依赖 (0,0) 是包围盒左上角或属于形状。
func _refresh_geometry() -> void:
	var local_rect: Rect2i = _display_snapshot.get("local_rect", item_instance_data.get_local_shape_rect())
	var rotated_rect: Rect2i = _display_snapshot.get("rotated_rect", item_instance_data.get_rotated_shape_rect())
	var box_pixel_size := Vector2(rotated_rect.size) * _item_box_size
	custom_minimum_size = box_pixel_size
	size = box_pixel_size
	center_pos = box_pixel_size / 2
	var texture_pixel_size := Vector2(local_rect.size) * _item_texture_size
	_panel_container.custom_minimum_size = texture_pixel_size
	_panel_container.size = texture_pixel_size
	# 盒子左上角在旋转包围盒 min 格，面板预旋转左上角在局部 min 格，
	# 故面板在盒内偏移 (局部 min - 旋转 min) 格；旋转轴取 (0,0) 锚点格中心
	#（与占格旋转语义一致），面板局部坐标下该轴位于 -局部 min 格加半格处。
	_panel_container.position = Vector2(local_rect.position - rotated_rect.position) * _item_texture_size
	_panel_container.pivot_offset = -Vector2(local_rect.position) * _item_texture_size + _item_texture_size / 2


#region 图标延迟显示（动画演出用）
## 持有图标隐藏状态；返回仅释放本次持有的幂等回调。与计时延迟独立，
## 旧动画结束不能解除其它动画的隐藏；只影响显示，不修改物品或输入。
func acquire_icon_display_hold() -> Callable:
	_ensure_ui_nodes()
	_next_icon_display_hold += 1
	var token := _next_icon_display_hold
	_icon_display_holds[token] = true
	icon_view.visible = false
	label.visible = false
	return _release_icon_display_hold.bind(token)


func _release_icon_display_hold(token: int) -> void:
	if not _icon_display_holds.erase(token):
		return
	if not _icon_display_holds.is_empty() or _is_icon_display_delayed:
		return
	delay_icon_display(0.0)



## 延迟图标显示：立即隐藏图标与数量标签，duration 秒后自动显现并短促淡入。
## 只隐藏图标层（ItemIconView + Label）——空 PanelContainer 本就透明，格子占位与布局不受影响。
## 时间型自动恢复：动画被跳过或中断也不会让图标永久隐藏；重复调用杀旧建新、重头计时。
func delay_icon_display(duration: float, fade_in_time: float = 0.12) -> void:
	_ensure_ui_nodes()
	_kill_icon_delay_tween()
	_is_icon_display_delayed = true
	icon_view.visible = false
	label.visible = false
	icon_view.modulate.a = 0.0
	label.modulate.a = 0.0
	_icon_delay_tween = create_tween()
	_icon_delay_tween.tween_interval(maxf(duration, 0.0))
	_icon_delay_tween.tween_callback(_reveal_icon_display)
	_icon_delay_tween.parallel().tween_property(icon_view, "modulate:a", 1.0, fade_in_time)
	_icon_delay_tween.parallel().tween_property(label, "modulate:a", 1.0, fade_in_time)


## 图标延迟到期：复位延迟标志并恢复图标可见性（数量标签经 update_item_num_label 重新判定），淡入由 tween 后续步接管。
func _reveal_icon_display() -> void:
	_is_icon_display_delayed = false
	if !is_instance_valid(icon_view):
		return
	icon_view.visible = _icon_display_holds.is_empty()
	if item_instance_data != null:
		update_item_num_label(item_instance_data.num)
	else:
		label.visible = false


func _kill_icon_delay_tween() -> void:
	if _icon_delay_tween != null and _icon_delay_tween.is_valid():
		_icon_delay_tween.kill()
	_icon_delay_tween = null
#endregion

func update_item_num_label(num: int) -> void:
	label.text = str(num)
	label.visible = num > 1 and not _is_icon_display_delayed and _icon_display_holds.is_empty()
	if num == 0:
		item_box_freed.emit()
		queue_free()

func update_item_rotate(direction: Vector2) -> void:
	if !is_instance_valid(_panel_container) or !is_instance_valid(label):
		return
	_refresh_geometry()
	_panel_container.rotation = ShapeTransform.dir_to_rotation_angle(direction)
	_apply_label_counter_rotation()
	if is_inside_tree():
		call_deferred("_apply_label_counter_rotation")

## 以标签中心为轴反向旋转，抵消面板旋转。
func _apply_label_counter_rotation() -> void:
	if !is_instance_valid(_panel_container) or !is_instance_valid(label):
		return
	label.pivot_offset = label.size * 0.5
	label.rotation = -_panel_container.rotation

## 标签尺寸变化后重新应用反向旋转。
func _on_label_resized() -> void:
	_apply_label_counter_rotation()

## 确保 UI 节点存在，支持纯代码创建 InventoryItemBox。
func _ensure_ui_nodes() -> void:
	if is_instance_valid(icon_view) and is_instance_valid(label):
		if !is_instance_valid(_panel_container):
			_panel_container = icon_view.get_parent() as PanelContainer
		_connect_label_resized_signal()
		return
	z_index = 1
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if !is_instance_valid(_panel_container):
		_panel_container = get_node_or_null("PanelContainer") as PanelContainer
		if !is_instance_valid(_panel_container):
			_panel_container = _create_panel_container()
			add_child(_panel_container)
	if !is_instance_valid(icon_view):
		icon_view = _panel_container.get_node_or_null("IconView") as ItemIconView
		if !is_instance_valid(icon_view):
			icon_view = _create_icon_view()
			_panel_container.add_child(icon_view)
	if !is_instance_valid(label):
		label = _panel_container.get_node_or_null("Label") as Label
		if !is_instance_valid(label):
			label = _create_label()
			_panel_container.add_child(label)
	_connect_label_resized_signal()

## 监听标签尺寸变化，确保布局后反向旋转仍有效。
func _connect_label_resized_signal() -> void:
	if !is_instance_valid(label):
		return
	if !label.resized.is_connected(_on_label_resized):
		label.resized.connect(_on_label_resized)

## 创建与场景资源一致的 PanelContainer。
func _create_panel_container() -> PanelContainer:
	var panel_container := PanelContainer.new()
	panel_container.name = "PanelContainer"
	panel_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_container.add_theme_stylebox_override("panel", _create_panel_style())
	panel_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel_container.offset_right = 39.0
	panel_container.offset_bottom = 36.0
	return panel_container

## 创建与场景资源一致的 ItemIconView。
func _create_icon_view() -> ItemIconView:
	var icon_view_node := ItemIconView.new()
	icon_view_node.name = "IconView"
	icon_view_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_view_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_view_node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return icon_view_node

## 创建与场景资源一致的 Label。
func _create_label() -> Label:
	var label_node := Label.new()
	label_node.name = "Label"
	label_node.modulate = Color(0.94, 0, 0, 1)
	label_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label_node.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label_node.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	label_node.text = "00"
	label_node.label_settings = LabelSettings.new()
	return label_node

## 创建与场景资源一致的 Panel 样式。
func _create_panel_style() -> StyleBoxFlat:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.6, 0.6, 0.6, 0)
	panel_style.corner_radius_top_left = 4
	panel_style.corner_radius_top_right = 4
	panel_style.corner_radius_bottom_right = 4
	panel_style.corner_radius_bottom_left = 4
	panel_style.corner_detail = 1
	return panel_style


func _disconnect_item_signals() -> void:
	if item_instance_data == null:
		return
	for pair in [[item_instance_data.num_changed, update_item_num_label], [item_instance_data.dir_changed, update_item_rotate], [item_instance_data.shape_changed, refresh_display]]:
		if pair[0].is_connected(pair[1]):
			pair[0].disconnect(pair[1])
