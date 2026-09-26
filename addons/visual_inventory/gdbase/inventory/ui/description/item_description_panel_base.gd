@abstract
class_name ItemDescriptionPanelBase
extends InventoryItemDescriptionPresenter
## 仅呈现显式传入的物品；悬停、延时和 Host 绑定归描述 Feature。
signal to_show_new
signal description_updated
signal description_refreshed
var _refresh_queued := false
var _presentation_pending := false

## 浮窗显隐控件；外部关闭时同时解除固定请求。固定详情栏可留空。
@export var visibility_control: Control

func _ready() -> void:
	if visibility_control != null:
		visibility_control.visibility_changed.connect(_on_visibility_changed)

func _on_visibility_changed() -> void:
	if visibility_control != null and not visibility_control.visible and item_instance_data != null:
		dismiss_inventory_item()

@export var item_instance_data: ItemInstanceData:
	set(value):
		_set_item_connections(item_instance_data, false)
		item_instance_data = value
		_set_item_connections(item_instance_data, true)
		_presentation_pending = value != null
		if !is_node_ready():
			await ready
		_try_update_description()

func _set_item_connections(item: ItemInstanceData, enabled: bool) -> void:
	if item == null:
		return
	for changed_signal in [item.num_changed, item.dir_changed, item.shape_changed]:
		if enabled and not changed_signal.is_connected(_on_item_changed):
			changed_signal.connect(_on_item_changed)
		elif not enabled and changed_signal.is_connected(_on_item_changed):
			changed_signal.disconnect(_on_item_changed)

func _exit_tree() -> void:
	_set_item_connections(item_instance_data, false)

func _on_item_changed(_value: Variant = null) -> void:
	refresh_inventory_item()

func refresh_inventory_item() -> void:
	if item_instance_data == null or not is_inside_tree() or _refresh_queued:
		return
	_refresh_queued = true
	_flush_description_refresh.call_deferred()

func _flush_description_refresh() -> void:
	_refresh_queued = false
	if is_inside_tree() and not is_queued_for_deletion() and item_instance_data != null:
		_try_update_description(true)

func _finish_description_update(content_only: bool) -> void:
	if _presentation_pending or not content_only:
		_presentation_pending = false
		description_updated.emit()
	else:
		description_refreshed.emit()

func get_item_instance_data() -> ItemInstanceData:
	return item_instance_data

func present_inventory_item(item: ItemInstanceData) -> bool:
	if item == null:
		return false
	item_instance_data = item
	return true

func clear_inventory_item() -> void:
	item_instance_data = null
	to_show_new.emit()

func is_pointer_over_panel() -> bool:
	if !is_inside_tree():
		return false
	var mouse_pos := get_viewport().get_mouse_position()
	for hit_control in _get_description_hit_controls():
		if is_instance_valid(hit_control) and hit_control.is_visible_in_tree() and hit_control.get_global_rect().has_point(mouse_pos):
			return true
	return false

## 收集用于命中检测的说明面板控件。
func _get_description_hit_controls() -> Array[Control]:
	var hit_controls: Array[Control] = []
	for child in get_children():
		if child is Control:
			hit_controls.append(child as Control)
	var box_container_value: Variant = get("box_container")
	if box_container_value is Control:
		var box_control := box_container_value as Control
		if !hit_controls.has(box_control):
			hit_controls.append(box_control)
		var box_parent := box_control.get_parent()
		while box_parent is Control:
			var parent_control := box_parent as Control
			if parent_control == self:
				break
			if !hit_controls.has(parent_control):
				hit_controls.append(parent_control)
			box_parent = parent_control.get_parent()
	return hit_controls

func _try_update_description(content_only: bool = false):
	_finish_description_update(content_only)
