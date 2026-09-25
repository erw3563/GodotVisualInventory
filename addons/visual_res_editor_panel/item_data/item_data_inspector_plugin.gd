@tool
extends EditorInspectorPlugin
const Session = preload("res://addons/visual_res_editor_panel/item_data/item_data_editor_session.gd")
const EditorPanel = preload("res://addons/visual_res_editor_panel/item_data/item_data_editor_panel.gd")
const Chrome = preload("res://addons/visual_res_editor_panel/visual_res_editor_popup.gd")
var undo_manager: EditorUndoRedoManager
var windows: Dictionary = {}

func _can_handle(object: Object) -> bool:
	return object is ItemData

func _parse_begin(object: Object) -> void:
	var button := Button.new()
	button.text = "打开物品创建器"
	button.pressed.connect(open_editor.bind(object))
	add_custom_control(button)

func open_editor(resource: ItemData) -> Window:
	var key := resource.get_instance_id()
	if windows.has(key) and is_instance_valid(windows[key]):
		windows[key].grab_focus()
		return windows[key]
	var window := Window.new()
	window.title = "物品创建器 · " + resource.item_name
	window.transient = true
	window.min_size = Vector2i(800, 520)
	window.size = Vector2i(1100, 760).min(DisplayServer.screen_get_usable_rect().size - Vector2i(48, 64))
	var session := Session.new()
	session.setup(resource, undo_manager)
	var panel := EditorPanel.new()
	panel.setup(session)
	Chrome.mount_window_content(window, Chrome.wrap_editor_content_surface(panel))
	windows[key] = window
	window.set_meta("editor_panel", panel)
	window.set_meta("editor_session", session)
	window.close_requested.connect(panel.request_close)
	panel.close_requested.connect(_close_window.bind(key))
	panel.new_requested.connect(func(): open_editor(ItemData.new()))
	window.tree_exited.connect(func(): windows.erase(key))
	EditorInterface.get_base_control().add_child(window)
	window.popup_centered()
	return window

func _close_window(key: int) -> void:
	if not windows.has(key):
		return
	var window: Window = windows[key]
	windows.erase(key)
	if is_instance_valid(window):
		window.get_meta("editor_panel").shutdown()
		window.hide()
		window.queue_free()

func clear_sessions() -> void:
	for key in windows.keys():
		_close_window(key)
