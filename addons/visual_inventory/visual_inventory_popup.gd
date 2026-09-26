@tool
extends RefCounted

const DEFAULT_POPUP_SIZE := Vector2i(720, 720)
const DEFAULT_MIN_SIZE := Vector2i(320, 320)
const WINDOW_CONTENT_MARGIN := 14


## 在编辑器主窗口中弹出可视化面板。
func open_panel(
	panel: Control,
	title: String,
	preferred_size: Vector2i = DEFAULT_POPUP_SIZE
) -> Window:
	var popup_window := Window.new()
	popup_window.title = title
	popup_window.size = preferred_size
	popup_window.min_size = DEFAULT_MIN_SIZE
	popup_window.transient = true
	popup_window.unresizable = false
	mount_window_content(popup_window, panel)
	popup_window.close_requested.connect(popup_window.hide)
	popup_window.close_requested.connect(popup_window.queue_free)
	EditorInterface.get_base_control().add_child(popup_window)
	popup_window.popup_centered()
	return popup_window


## 独立编辑窗口共用边距，内容区与窗口外框留出统一间距。
static func mount_window_content(window: Window, content: Control, margin: int = WINDOW_CONTENT_MARGIN) -> MarginContainer:
	var container := MarginContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		container.add_theme_constant_override("margin_" + side, margin)
	window.add_child(container)
	prepare_panel_for_popup(content)
	container.add_child(content)
	return container


## 弹窗内容作为 Container 子节点时只用尺寸标志填满，避免锚点与容器布局互相抢尺寸。
static func prepare_panel_for_popup(panel: Control) -> void:
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.anchor_right = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = 0
	panel.offset_top = 0
	panel.offset_right = 0
	panel.offset_bottom = 0
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL


## 用 TabContainer 面板底色包裹内容，与 Host 可视化编辑器内容区对齐。
static func wrap_editor_content_surface(content: Control) -> PanelContainer:
	var surface := PanelContainer.new()
	surface.name = "EditorContentSurface"
	prepare_panel_for_popup(surface)
	apply_editor_content_surface(surface)
	var host := EditorInterface.get_base_control()
	var refresh := func():
		if is_instance_valid(surface):
			apply_editor_content_surface(surface)
	host.theme_changed.connect(refresh)
	surface.tree_exiting.connect(func():
		if host.theme_changed.is_connected(refresh):
			host.theme_changed.disconnect(refresh)
	)
	prepare_panel_for_popup(content)
	surface.add_child(content)
	return surface


## 套用编辑器 TabContainer 面板样式作为内容区底色。
static func apply_editor_content_surface(panel: PanelContainer) -> void:
	if panel.get_meta("_applying_content_surface", false):
		return
	panel.set_meta("_applying_content_surface", true)
	var host := EditorInterface.get_base_control()
	var style: StyleBox = host.get_theme_stylebox(&"panel", &"TabContainer")
	if style == null:
		style = host.get_theme_stylebox(&"panel", &"Panel")
	if style != null:
		panel.add_theme_stylebox_override(&"panel", style.duplicate())
	panel.set_meta("_applying_content_surface", false)


## 列表控件与窗口内容区共用同一背景表面。
static func flatten_list_surface(control: Control) -> void:
	control.add_theme_stylebox_override("panel", StyleBoxEmpty.new())


## 预览底板使用编辑器主题深色，随主题切换更新。
static func editor_preview_surface_color(from_control: Control) -> Color:
	return from_control.get_theme_color(&"dark_color_2", &"Editor")
