@tool
extends EditorProperty

const PANEL_SCENE := preload(
	"res://addons/visual_inventory/occupy/visual_occupy_map_res_editor_panel.tscn"
)
const VisualInventoryPopup := preload("res://addons/visual_inventory/visual_inventory_popup.gd")

const POPUP_TITLE := "OccupyMap 可视化编辑"
const POPUP_SIZE := Vector2i(720, 720)

var occupy_map_resource: OccupyMap
var panel: Control
var popup_window: Window
var popup_panel: Control
var popup_helper: VisualInventoryPopup


func _init() -> void:
	panel = PANEL_SCENE.instantiate() as Control
	add_child(panel)
	set_bottom_editor(panel)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_close_popup()


## 绑定当前正在检查器中编辑的 OccupyMap 资源。
func setup_occupy_map_resource(new_occupy_map_resource: OccupyMap) -> void:
	occupy_map_resource = new_occupy_map_resource
	_connect_panel_signals()
	_sync_panel_state()


## 当检查器属性刷新时，同步最新 cells 数据到面板实例。
func _update_property() -> void:
	var edited_occupy_map_resource := get_edited_object() as OccupyMap
	if edited_occupy_map_resource != null:
		occupy_map_resource = edited_occupy_map_resource

	_sync_panel_state()


## 接收可视化面板提交的 cells 修改。
func _on_panel_cells_changed(new_cells: Array) -> void:
	var normalized_cells := _get_normalized_cells(new_cells)
	emit_changed(get_edited_property(), normalized_cells)
	_sync_panel_state(normalized_cells)


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

	if panel.has_signal("cells_changed") and !panel.is_connected("cells_changed", _on_panel_cells_changed):
		panel.connect("cells_changed", _on_panel_cells_changed)
	if panel.has_signal("popup_requested") and !panel.is_connected("popup_requested", _on_popup_requested):
		panel.connect("popup_requested", _on_popup_requested)


func _connect_popup_panel_signals() -> void:
	if popup_panel == null:
		return
	if popup_panel.has_signal("cells_changed") and !popup_panel.is_connected("cells_changed", _on_panel_cells_changed):
		popup_panel.connect("cells_changed", _on_panel_cells_changed)


func _sync_panel_state(override_cells: Variant = null) -> void:
	if occupy_map_resource == null:
		return

	_apply_panel_state(panel, override_cells)
	if popup_panel != null and is_instance_valid(popup_panel):
		_apply_panel_state(popup_panel, override_cells)


func _apply_panel_state(target_panel: Control, override_cells: Variant = null) -> void:
	if target_panel == null or occupy_map_resource == null:
		return

	var current_cells: Array = occupy_map_resource.cells
	if override_cells is Array:
		current_cells = override_cells

	var normalized_cells := _get_normalized_cells(current_cells)
	target_panel.set_meta("occupy_map_resource", occupy_map_resource)
	target_panel.set_meta("cells", normalized_cells)

	if target_panel.has_method("set_occupy_map_resource"):
		target_panel.call("set_occupy_map_resource", occupy_map_resource)
	if target_panel.has_method("set_cells"):
		target_panel.call("set_cells", normalized_cells)


func _close_popup() -> void:
	if popup_window != null and is_instance_valid(popup_window):
		popup_window.queue_free()


func _on_popup_tree_exited() -> void:
	popup_window = null
	popup_panel = null
	popup_helper = null


func _get_normalized_cells(input_cells: Array) -> Array[Vector2i]:
	var normalized_cells: Array[Vector2i] = []
	for cell in input_cells:
		if cell is Vector2i and !normalized_cells.has(cell):
			normalized_cells.append(cell)
	return normalized_cells
