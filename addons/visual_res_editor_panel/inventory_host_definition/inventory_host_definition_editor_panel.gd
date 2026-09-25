@tool
extends VBoxContainer
const LayoutPanel = preload("res://addons/visual_res_editor_panel/inventory_host_definition/inventory_host_layout_editor_panel.gd")
const FeaturePanel = preload("res://addons/visual_res_editor_panel/inventory_host_definition/inventory_host_feature_editor_panel.gd")
signal close_requested
var session: RefCounted
var layout_panel: Control
var feature_panel: Control
var tabs: TabContainer
var status: Label
var apply_button: Button
var close_dialog: ConfirmationDialog

func setup(value: RefCounted) -> void:
	session = value
	session.changed.connect(update_status)

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 8)
	var toolbar := HBoxContainer.new()
	add_child(toolbar)
	apply_button = _button(toolbar, "应用", apply_changes)
	_button(toolbar, "重新载入", request_reload)
	_button(toolbar, "关闭", request_close)
	tabs = TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)
	layout_panel = LayoutPanel.new()
	layout_panel.name = "布局"
	layout_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout_panel.setup(session)
	tabs.add_child(layout_panel)
	feature_panel = FeaturePanel.new()
	feature_panel.name = "功能"
	feature_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feature_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	feature_panel.setup(session)
	tabs.add_child(feature_panel)
	tabs.tab_changed.connect(func(index: int):
		if index != 0:
			layout_panel.preview.stop()
		else:
			layout_panel.preview.request_layout(session.draft)
	)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(status)
	layout_panel.preview.validation_changed.connect(func(_problem: String): update_status())
	update_status()

func update_status() -> void:
	if not is_instance_valid(status):
		return
	var error: String = session.validation_error()
	if error.is_empty() and session.layout_dirty() and is_instance_valid(layout_panel.preview):
		error = layout_panel.preview.problem
	var notes: Array[String] = []
	for item in session.diagnostics():
		if item.has("note") and item.note not in notes:
			notes.append(item.note)
	var sync_text := "有未应用修改" if session.is_dirty() else "已同步"
	status.text = error if not error.is_empty() else sync_text + " · 静态配置有效" + ("；运行时依赖待验证。" if not notes.is_empty() else "。")
	status.tooltip_text = "\n".join(notes)
	apply_button.disabled = not error.is_empty() or not session.is_dirty()

func apply_changes() -> bool:
	# 已知标准布局有静态检查；自定义脏布局需沿用真实隔离预览验证。
	if session.layout_dirty():
		layout_panel.preview._refresh()
		if not layout_panel.preview.problem.is_empty():
			status.text = layout_panel.preview.problem
			return false
	var error: String = session.apply()
	if not error.is_empty():
		status.text = error
		return false
	return true

func request_reload() -> void:
	if not session.is_dirty():
		session.reload()
		return
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "放弃布局与功能两栏的未应用修改并重新载入？"
	add_child(dialog)
	dialog.confirmed.connect(func():
		session.reload()
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func request_close() -> void:
	if not session.is_dirty():
		close_requested.emit()
		return
	if is_instance_valid(close_dialog):
		close_dialog.popup_centered()
		return
	close_dialog = ConfirmationDialog.new()
	close_dialog.dialog_text = "布局或功能有未应用修改。"
	close_dialog.ok_button_text = "应用并关闭"
	close_dialog.cancel_button_text = "返回编辑"
	close_dialog.add_button("放弃修改", true, "discard")
	add_child(close_dialog)
	close_dialog.confirmed.connect(func():
		if apply_changes():
			close_requested.emit()
	)
	close_dialog.custom_action.connect(func(action: StringName):
		if action == &"discard":
			close_requested.emit()
	)
	close_dialog.popup_centered()

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func shutdown() -> void:
	if is_instance_valid(layout_panel):
		layout_panel.shutdown()
	if is_instance_valid(feature_panel):
		feature_panel.shutdown()
	if session != null and session.changed.is_connected(update_status):
		session.changed.disconnect(update_status)

func _exit_tree() -> void:
	shutdown()
