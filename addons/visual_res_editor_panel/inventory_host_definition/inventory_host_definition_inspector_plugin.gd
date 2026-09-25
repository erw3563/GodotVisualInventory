@tool
extends EditorInspectorPlugin
const Session = preload("res://addons/visual_res_editor_panel/inventory_host_definition/inventory_host_definition_editor_session.gd")
const EditorPanel = preload("res://addons/visual_res_editor_panel/inventory_host_definition/inventory_host_definition_editor_panel.gd")
const Chrome = preload("res://addons/visual_res_editor_panel/visual_res_editor_popup.gd")
var undo_manager: EditorUndoRedoManager
var windows: Dictionary = {}

func _can_handle(object: Object) -> bool:
	return object is InventoryHostDefinition

func _parse_begin(object: Object) -> void:
	add_custom_control(create_launcher(object))

func create_launcher(resource: InventoryHostDefinition) -> Button:
	var button := Button.new()
	button.text = "打开可视化编辑器"
	button.tooltip_text = "在独立弹窗中配置库存 Host 的布局与功能"
	button.pressed.connect(open_editor.bind(resource))
	return button

func open_editor(resource: InventoryHostDefinition) -> Window:
	var key := resource.get_instance_id()
	if windows.has(key) and is_instance_valid(windows[key]):
		windows[key].grab_focus()
		return windows[key]
	var window := Window.new()
	window.title = "InventoryHostDefinition 可视化编辑器"
	window.transient = true
	window.min_size = Vector2i(640, 480)
	var usable := DisplayServer.screen_get_usable_rect()
	window.size = Vector2i(1200, 820).min(usable.size - Vector2i(48, 64))
	var session := Session.new()
	session.setup(resource, undo_manager)
	var panel := EditorPanel.new()
	panel.setup(session)
	Chrome.mount_window_content(window, panel)
	windows[key] = window
	window.set_meta("editor_panel", panel)
	window.set_meta("editor_session", session)
	window.close_requested.connect(panel.request_close)
	panel.close_requested.connect(_close_window.bind(key))
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
		var panel: Control = window.get_meta("editor_panel")
		panel.shutdown()
		window.hide()
		window.queue_free()

func clear_sessions() -> void:
	for key in windows.keys():
		_close_window(key)
