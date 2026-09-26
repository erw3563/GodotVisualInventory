@tool
extends EditorProperty

const PANEL_SCENE := preload(
	"res://addons/visual_inventory/inventory_data/visual_inventory_data_editor_panel.tscn"
)
const VisualInventoryPopup := preload("res://addons/visual_inventory/visual_inventory_popup.gd")

const POPUP_TITLE := "InventoryData 可视化编辑"
const POPUP_SIZE := Vector2i(900, 720)

var inventory_data_resource: InventoryData
var panel: Control
var popup_window: Window
var popup_panel: Control
var popup_helper: VisualInventoryPopup
var _is_commit_queued: bool = false


func _init() -> void:
	set_process(false)
	panel = PANEL_SCENE.instantiate() as Control
	add_child(panel)
	set_bottom_editor(panel)
	set_label("")


## 手持是尚未结束的编辑操作；Inspector 重建会让旧面板恢复来源物品。
## 因此在放下、删除或恢复之后才提交，不能保存暂时缺少手持物品的库存。
func _process(_delta: float) -> void:
	if _is_commit_queued and not _has_pending_held_item():
		_commit_inventory_changes()


func _has_pending_held_item() -> bool:
	var services := InventorySceneServices.find_existing(panel)
	if services == null:
		return false
	var session := services.get_held_item_session()
	return is_instance_valid(session) and session.is_holding_from(inventory_data_resource)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_close_popup()


## 绑定当前正在检查器中编辑的 InventoryData 资源。
func setup_inventory_data_resource(new_inventory_data_resource: InventoryData) -> void:
	inventory_data_resource = new_inventory_data_resource
	_connect_panel_signals()
	_sync_panel_state()


## 当检查器刷新时，同步最新背包数据到面板。
func _update_property() -> void:
	var edited_inventory_data := get_edited_object() as InventoryData
	if edited_inventory_data != null:
		inventory_data_resource = edited_inventory_data
	_sync_panel_state()


## 接收面板提交的背包修改；同一帧内多次改动合并为一次保存。
func _on_panel_inventory_changed() -> void:
	if inventory_data_resource == null:
		return
	if _is_commit_queued:
		return
	_is_commit_queued = true
	_commit_inventory_changes.call_deferred()


## 在弹窗中打开一份新的可视化面板实例。
func _on_popup_requested() -> void:
	if popup_window != null and is_instance_valid(popup_window):
		popup_window.grab_focus()
		return

	popup_helper = VisualInventoryPopup.new()
	popup_panel = PANEL_SCENE.instantiate() as Control
	popup_window = popup_helper.open_panel(popup_panel, POPUP_TITLE, POPUP_SIZE)
	popup_window.tree_exited.connect(_on_popup_tree_exited)

	_connect_popup_panel_signals()
	_sync_panel_state()


func _connect_panel_signals() -> void:
	if panel == null:
		return
	if panel.has_signal("inventory_changed") and !panel.is_connected("inventory_changed", _on_panel_inventory_changed):
		panel.connect("inventory_changed", _on_panel_inventory_changed)
	if panel.has_signal("popup_requested") and !panel.is_connected("popup_requested", _on_popup_requested):
		panel.connect("popup_requested", _on_popup_requested)


func _connect_popup_panel_signals() -> void:
	if popup_panel == null:
		return
	if popup_panel.has_signal("inventory_changed") and !popup_panel.is_connected("inventory_changed", _on_panel_inventory_changed):
		popup_panel.connect("inventory_changed", _on_panel_inventory_changed)


func _sync_panel_state() -> void:
	if inventory_data_resource == null:
		return
	_apply_panel_state(panel)
	if popup_panel != null and is_instance_valid(popup_panel):
		_apply_panel_state(popup_panel)


func _apply_panel_state(target_panel: Control) -> void:
	if target_panel == null or inventory_data_resource == null:
		return
	target_panel.set_meta("inventory_data_resource", inventory_data_resource)
	if target_panel.has_method("set_inventory_data_resource"):
		target_panel.call("set_inventory_data_resource", inventory_data_resource)


## 把当前背包改动立即写回资源，再通知检查器。
func _commit_inventory_changes() -> void:
	if not _is_commit_queued:
		return
	if inventory_data_resource == null:
		_is_commit_queued = false
		set_process(false)
		return
	if _has_pending_held_item():
		set_process(true)
		return
	_is_commit_queued = false
	set_process(false)
	_persist_inventory_resource()
	# occupancy 为权威；提交前对齐派生缓存，再通知检查器。
	inventory_data_resource.ensure_occupancy_synced()
	emit_changed("occupy_map", inventory_data_resource.occupy_map)
	var committed_items: Array[ItemInstanceData] = []
	for item_instance in inventory_data_resource.get_item_instances():
		committed_items.append(item_instance)
	emit_changed("item_instances", committed_items)
	inventory_data_resource.emit_changed()
	_sync_panel_state()


## 立即保存独立 .tres；内嵌子资源则把当前场景标为未保存。
func _persist_inventory_resource() -> void:
	if inventory_data_resource == null:
		return
	var resource_path := inventory_data_resource.resource_path
	if resource_path.is_empty() or resource_path.contains("::"):
		EditorInterface.mark_scene_as_unsaved()
		return
	var save_error := ResourceSaver.save(inventory_data_resource, resource_path)
	if save_error != OK:
		push_error("保存背包资源失败: %s，错误 %s" % [resource_path, error_string(save_error)])


func _close_popup() -> void:
	if popup_window != null and is_instance_valid(popup_window):
		popup_window.queue_free()


func _on_popup_tree_exited() -> void:
	popup_window = null
	popup_panel = null
	popup_helper = null
