@tool
class_name InventoryHeldItemView
extends Control
## InventoryHeldItemView 负责显示鼠标手持物品的视觉层（仅跟随显示）。

## 手持物品透明度，略微透明可减少遮挡感。
@export_range(0.1, 1.0, 0.01) var held_item_alpha: float = 0.9
## 手持物品缩放，略微放大可增强“拿起”反馈。
@export_range(0.8, 1.4, 0.01) var held_item_scale: float = 1.06

## 当前显示中的手持物品框。
var held_item_box: InventoryItemBox
## 当前手持物品数据引用（仅用于显示）。
var held_item_instance_data: ItemInstanceData
## 当前手持物品图标尺寸。
var held_item_texture_size: Vector2 = Vector2(32, 32)
## 当前手持物品格子尺寸。
var held_item_box_size: Vector2 = Vector2(32, 32)
## 手持物品中心偏移，用于把中心对齐到鼠标。
var held_item_center_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	z_index = 100


func _process(_delta: float) -> void:
	if Engine.is_editor_hint() and !visible:
		return
	if !_is_ready_for_view_operations():
		return
	_update_follow_position()


## 设置手持物品显示。
func set_display_item(
	item_instance_data: ItemInstanceData,
	item_texture_size: Vector2,
	item_box_size: Vector2
) -> void:
	clear_held_item()
	if !is_instance_valid(item_instance_data):
		return
	held_item_instance_data = item_instance_data
	held_item_texture_size = item_texture_size
	held_item_box_size = item_box_size
	held_item_box = InventoryItemBox.new()
	held_item_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	held_item_box.modulate = Color(1.0, 1.0, 1.0, held_item_alpha)
	held_item_box.scale = Vector2(held_item_scale, held_item_scale)
	held_item_box.init_cell(item_instance_data, item_texture_size, item_box_size)
	held_item_box.icon_view.set_sync_callback(_sync_item_view)
	# 中心偏移须在 init_cell 之后取值（布局计算后才有效），手持物品以包围盒中心对齐鼠标。
	held_item_center_offset = held_item_box.get_center() * held_item_scale
	add_child(held_item_box)
	visible = true
	if _is_ready_for_view_operations():
		_update_follow_position()


## 当前是否存在手持物品显示。
func has_held_item() -> bool:
	return is_instance_valid(held_item_instance_data)


## 获取当前手持物品数据。
func get_held_item_instance_data() -> ItemInstanceData:
	return held_item_instance_data


## 清理手持物品显示。
func clear_held_item() -> void:
	if is_instance_valid(held_item_box):
		held_item_box.queue_free()
	held_item_box = null
	held_item_instance_data = null
	held_item_texture_size = Vector2(32, 32)
	held_item_box_size = Vector2(32, 32)
	held_item_center_offset = Vector2.ZERO
	visible = false


## 更新手持物品跟随鼠标的位置。
func _update_follow_position() -> void:
	if !is_instance_valid(held_item_box) or !_is_ready_for_view_operations():
		return
	global_position = get_global_mouse_position() - held_item_center_offset


## 节点是否已挂载到有效视口，可安全读取鼠标与场景树。
func _is_ready_for_view_operations() -> bool:
	return is_inside_tree() and get_viewport() != null


var view_provider: InventoryItemViewProvider

func _sync_item_view(item: ItemInstanceData, view: ItemIconView) -> void:
	if view_provider != null:
		view_provider.sync_view(item, view)

func get_item_views(item: ItemInstanceData) -> Array[ItemIconView]:
	if is_instance_valid(held_item_box) and not held_item_box.is_queued_for_deletion() and held_item_box.icon_view.get_bound_item() == item:
		return [held_item_box.icon_view]
	return []
