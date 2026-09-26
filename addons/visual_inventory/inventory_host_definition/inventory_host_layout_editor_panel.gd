@tool
extends VBoxContainer
const Catalog = preload("res://addons/visual_inventory/inventory_host_definition/inventory_host_layout_editor_catalog.gd")
const Preview = preload("res://addons/visual_inventory/inventory_host_definition/inventory_host_layout_preview.gd")
const Chrome = preload("res://addons/visual_inventory/visual_inventory_popup.gd")

var session: RefCounted
var preview: SubViewportContainer
var parts_box: VBoxContainer
var edit_box: VBoxContainer
var style_detail: VBoxContainer
var detail_title_label: Label
var style_inspector: EditorInspector
var style_create_row: HBoxContainer
var style_empty_label: Label
var title_label: Label
var status: Label
var outer_split: HSplitContainer
var parts_and_edit: VSplitContainer
var preview_and_style: HSplitContainer

var reference_edit: Button
var unique_button: Button
var type_picker: OptionButton
var layout_picker: EditorResourcePicker
var controls: Dictionary = {}
var detail_select_buttons: Dictionary = {}
var selected_detail_key: String = "cell_style"
var selected_edit_group: String = ""
var edit_group_bodies: Dictionary = {}
var orbit_bar: HBoxContainer
var _preview_style: StyleBoxFlat

var last_type: Script
var _updating := false
var _built := false
var _preview_problem := ""
var _last_preview_stamp := ""
var _splits_initialized := false


func setup(value: RefCounted) -> void:
	session = value
	session.changed.connect(_session_changed)
	if is_inside_tree():
		_session_changed()

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _preview_style != null:
		_preview_style.bg_color = Chrome.editor_preview_surface_color(self)

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	clip_contents = true
	add_theme_constant_override("separation", 8)
	title_label = _label(self, "")
	title_label.add_theme_font_size_override("font_size", 19)
	var top := HBoxContainer.new()
	add_child(top)
	type_picker = OptionButton.new()
	type_picker.add_item("选择布局…")
	for text in Catalog.TITLES:
		type_picker.add_item(text)
	top.add_child(type_picker)
	type_picker.item_selected.connect(func(index: int):
		if not _updating and index > 0:
			session.select_type(index - 1)
	)
	_button(top, "新建当前类型", func():
		var index: int = Catalog.type_index(session.draft)
		if index >= 0:
			session.draft = Catalog.types()[index].new()
			session.make_unique()
	)
	var reference_row := HBoxContainer.new()
	add_child(reference_row)
	_label(reference_row, "布局资源")
	layout_picker = EditorResourcePicker.new()
	layout_picker.base_type = "InventoryPanelAssemblyDefinition"
	layout_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reference_row.add_child(layout_picker)
	layout_picker.resource_changed.connect(func(resource: Resource):
		if not _updating and resource != null:
			if not session.use_reference(resource):
				status.text = "请选择具体的库存布局资源。"
	)
	reference_edit = _button(reference_row, "编辑引用资源", func(): session.enable_reference_edit())
	unique_button = _button(reference_row, "复制为独有配置", func(): session.make_unique())
	outer_split = HSplitContainer.new()
	outer_split.name = "LayoutColumns"
	outer_split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer_split.clip_contents = true
	outer_split.split_offset = 220
	add_child(outer_split)
	parts_and_edit = VSplitContainer.new()
	parts_and_edit.name = "PartsAndEdit"
	parts_and_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parts_and_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parts_and_edit.clip_contents = true
	parts_and_edit.split_offset = 120
	outer_split.add_child(parts_and_edit)
	var parts_column := _column(parts_and_edit, "部件")
	parts_box = parts_column.get_meta("body")
	var edit_column := _column(parts_and_edit, "编辑")
	edit_box = edit_column.get_meta("body")
	preview_and_style = HSplitContainer.new()
	preview_and_style.name = "PreviewAndStyle"
	preview_and_style.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_and_style.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_and_style.clip_contents = true
	preview_and_style.split_offset = 420
	outer_split.add_child(preview_and_style)
	var preview_column := VBoxContainer.new()
	preview_column.name = "PreviewColumn"
	preview_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_column.clip_contents = true
	preview_column.add_theme_constant_override("separation", 6)
	preview_and_style.add_child(preview_column)
	_label(preview_column, "外观样例预览")
	var toolbar := HBoxContainer.new()
	preview_column.add_child(toolbar)
	_button(toolbar, "重置预览", func(): preview.reset_sample())
	_label(toolbar, "缩放")
	var zoom := SpinBox.new()
	zoom.min_value = 0.25
	zoom.max_value = 2.0
	zoom.step = 0.05
	zoom.value = 1.0
	toolbar.add_child(zoom)
	zoom.value_changed.connect(func(value: float):
		preview.view_zoom = value
		preview._position_mount()
	)
	_label(toolbar, "格子")
	var cell_size := SpinBox.new()
	cell_size.min_value = 16
	cell_size.max_value = 128
	cell_size.value = 48
	toolbar.add_child(cell_size)
	cell_size.value_changed.connect(func(value: float):
		preview.cell_pixels = value
		preview.request_layout(session.draft)
	)
	var background := PanelContainer.new()
	background.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	background.size_flags_vertical = Control.SIZE_EXPAND_FILL
	background.clip_contents = true
	var style := StyleBoxFlat.new()
	style.bg_color = Chrome.editor_preview_surface_color(self)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	background.add_theme_stylebox_override("panel", style)
	preview_column.add_child(background)
	_preview_style = style
	preview = Preview.new()
	background.add_child(preview)
	preview.validation_changed.connect(func(problem: String):
		_preview_problem = problem
		_update_status()
	)
	orbit_bar = HBoxContainer.new()
	preview_column.add_child(orbit_bar)
	_button(orbit_bar, "播放发牌", preview.play_deal)
	_button(orbit_bar, "停止并恢复", preview.stop)
	_button(orbit_bar, "开始试用", func(): preview.adapter.playing = true)
	_button(orbit_bar, "增加样例", func():
		if not preview.add_sample():
			status.text = "当前预览库存没有可添加的样例或空间。"
	)
	_button(orbit_bar, "移除样例", preview.remove_sample)
	var note := _label(preview_column, "固定使用默认样例；拨盘拖动只试用效果，不改变布局参数。")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	style_detail = VBoxContainer.new()
	style_detail.name = "StyleDetail"
	style_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	style_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	style_detail.clip_contents = true
	style_detail.add_theme_constant_override("separation", 6)
	preview_and_style.add_child(style_detail)
	detail_title_label = _label(style_detail, "当前样式属性")
	style_empty_label = _label(style_detail, "")
	style_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	style_empty_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	style_create_row = HBoxContainer.new()
	style_create_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	style_detail.add_child(style_create_row)
	style_inspector = EditorInspector.new()
	style_inspector.name = "StyleInspector"
	style_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	style_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	style_detail.add_child(style_inspector)
	style_inspector.property_edited.connect(func(_key: String):
		if not _updating:
			session.touch_layout()
	)
	# 仅在首次布局时设默认分割；之后完全交给 SplitContainer 与窗口尺寸。
	resized.connect(_initialize_splits_once)
	call_deferred("_initialize_splits_once")
	status = _label(self, "")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_built = true
	_session_changed()

## 带标题的可滚动列；不写死最小宽度，避免把窗口顶破。
func _column(parent: Node, title: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = title + "Column"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.clip_contents = true
	column.add_theme_constant_override("separation", 6)
	parent.add_child(column)
	_label(column, title)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	column.set_meta("body", body)
	return column

## 窗口首次获得有效尺寸时设置默认分割，不在后续 resized 中回写最小尺寸。
func _initialize_splits_once() -> void:
	if _splits_initialized:
		return
	if outer_split == null or parts_and_edit == null or preview_and_style == null:
		return
	if outer_split.size.x < 32.0 or preview_and_style.size.x < 32.0:
		return
	_splits_initialized = true
	outer_split.split_offset = int(outer_split.size.x * 0.22)
	parts_and_edit.split_offset = int(parts_and_edit.size.y * 0.28)
	preview_and_style.split_offset = int(preview_and_style.size.x * 0.68)

func _session_changed() -> void:
	if not _built or session == null:
		return
	_updating = true
	title_label.text = "布局 · " + (session.target.resource_path if not session.target.resource_path.is_empty() else "未保存的 InventoryHostDefinition")
	var index: int = Catalog.type_index(session.draft)
	type_picker.select(index + 1)
	layout_picker.edited_resource = session.layout_reference
	reference_edit.disabled = session.layout_reference == null or session.edit_reference
	unique_button.disabled = session.draft == null
	var script: Script = session.draft.get_script() if session.draft != null else null
	if script != last_type or controls.is_empty():
		last_type = script
		_build_fields()
	_sync_fields()
	_sync_detail()
	orbit_bar.visible = index == 2
	var preview_stamp := Catalog.fingerprint(session.draft)
	if preview_stamp != _last_preview_stamp:
		_last_preview_stamp = preview_stamp
		preview.request_layout(session.draft)
	_updating = false
	_update_status()

func _build_fields() -> void:
	controls.clear()
	detail_select_buttons.clear()
	edit_group_bodies.clear()
	_clear_box(parts_box)
	_clear_box(edit_box)
	if session.draft == null:
		_label(parts_box, "选择布局类型或引用已有布局资源。")
		_label(edit_box, "选择布局后在此编辑参数。")
		style_detail.visible = false
		return
	if session.draft is LogicInventoryPanelAssemblyDefinition:
		_label(parts_box, "逻辑布局没有部件开关。")
		_label(edit_box, "逻辑布局用于持续运行库存功能，首选尺寸为零。预览显示空布局。").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		style_detail.visible = false
		return
	var index: int = Catalog.type_index(session.draft)
	if index < 0:
		_label(parts_box, "自定义布局没有标准部件开关。")
		_label(edit_box, "引用资源只读时隐藏属性；选择编辑引用或复制独有后展开。").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var inspector := EditorInspector.new()
		inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
		edit_box.add_child(inspector)
		inspector.edit(session.draft if session.can_edit() else null)
		inspector.property_edited.connect(func(_key: String):
			session.changed.emit()
		)
		controls["_custom"] = inspector
		style_detail.visible = false
		return
	var properties := {}
	for info in session.draft.get_property_list():
		properties[str(info.name)] = info
	_fill_groups(parts_box, Catalog.parts_groups(session.draft), properties)
	if Catalog.parts_groups(session.draft).is_empty():
		_label(parts_box, "当前布局没有可配置的部件开关。")
	_fill_exclusive_groups(edit_box, Catalog.edit_groups(session.draft), properties)
	style_detail.visible = Catalog.supports_detail_panel(session.draft)
	if style_detail.visible and not Catalog.is_detail_key(selected_detail_key, session.draft):
		selected_detail_key = Catalog.default_detail_key(session.draft)

## 可折叠分组，用于部件列等多组可同时展开的区域。
func _fill_groups(target: VBoxContainer, groups: Dictionary, properties: Dictionary) -> void:
	for group in groups:
		var header := Button.new()
		header.text = "▾ " + group
		header.toggle_mode = true
		header.button_pressed = true
		header.alignment = HORIZONTAL_ALIGNMENT_LEFT
		target.add_child(header)
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 6)
		target.add_child(body)
		header.toggled.connect(func(open: bool):
			body.visible = open
		)
		for key in groups[group]:
			_add_field(body, key, properties[key])

## 编辑列互斥分组：同一时间只展开一组参数，用 OptionButton 下拉切换（与顶部布局类型选择同形态）。
func _fill_exclusive_groups(target: VBoxContainer, groups: Dictionary, properties: Dictionary) -> void:
	edit_group_bodies.clear()
	if groups.is_empty():
		return
	var group_names: Array = groups.keys()
	if selected_edit_group.is_empty() or not groups.has(selected_edit_group):
		selected_edit_group = str(group_names[0])
	var group_picker := OptionButton.new()
	group_picker.name = "EditGroupTabs"
	group_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target.add_child(group_picker)
	var selected_index := 0
	for group_index in group_names.size():
		var group_name := str(group_names[group_index])
		group_picker.add_item(group_name)
		if group_name == selected_edit_group:
			selected_index = group_index
		var body := VBoxContainer.new()
		body.name = group_name + "Body"
		body.add_theme_constant_override("separation", 6)
		body.visible = group_name == selected_edit_group
		target.add_child(body)
		edit_group_bodies[group_name] = body
		for key in groups[group_names[group_index]]:
			_add_field(body, key, properties[key])
	group_picker.select(selected_index)
	group_picker.item_selected.connect(func(index: int):
		var group_name := str(group_names[index])
		selected_edit_group = group_name
		for name in edit_group_bodies:
			edit_group_bodies[name].visible = name == group_name
		_on_edit_group_selected(group_name)
	)
	_on_edit_group_selected(selected_edit_group)

## 切换编辑分组时对齐右侧嵌套选中项。
func _on_edit_group_selected(group_name: String) -> void:
	if group_name == "背景":
		selected_detail_key = "background_style"
	elif group_name == "底板样式" and selected_detail_key not in ["cell_style", "empty_cell_style"]:
		selected_detail_key = "cell_style"
	elif group_name == "格子样式":
		selected_detail_key = "cell_style"
	elif group_name == "行外观" and selected_detail_key not in ["row_style", "row_hover_style", "row_material"]:
		selected_detail_key = "row_style"
	_sync_detail()

func _add_field(body: VBoxContainer, key: String, info: Dictionary) -> void:
	var field := VBoxContainer.new()
	body.add_child(field)
	var label: String = Catalog.field_label(session.draft, key)
	var editor: Control
	if info.type == TYPE_BOOL:
		var check := CheckBox.new()
		check.text = label
		check.toggled.connect(func(value: bool): _edit_field(key, value))
		editor = check
	else:
		if Catalog.is_detail_key(key, session.draft):
			var title_row := HBoxContainer.new()
			field.add_child(title_row)
			_label(title_row, label)
			var select := Button.new()
			select.toggle_mode = true
			select.text = "编辑"
			select.pressed.connect(func():
				selected_detail_key = key
				_sync_detail()
			)
			title_row.add_child(select)
			detail_select_buttons[key] = select
		else:
			_label(field, label)
		if info.type == TYPE_STRING and info.hint == PROPERTY_HINT_DIR:
			var row := HBoxContainer.new()
			var path := LineEdit.new()
			path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			path.placeholder_text = "未配置：显示空目录"
			path.text_changed.connect(func(value: String): _edit_field(key, value))
			row.add_child(path)
			var dialog := EditorFileDialog.new()
			dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_DIR
			dialog.access = EditorFileDialog.ACCESS_RESOURCES
			dialog.dir_selected.connect(func(value: String): _edit_field(key, value))
			row.add_child(dialog)
			_button(row, "选择目录…", func(): dialog.popup_centered_ratio(0.6))
			editor = row
		elif info.type == TYPE_VECTOR2 or info.type == TYPE_VECTOR2I:
			var row := HBoxContainer.new()
			var is_integer_vector: bool = info.type == TYPE_VECTOR2I
			for axis in 2:
				var axis_label := "水平" if axis == 0 else "垂直"
				if not is_integer_vector:
					axis_label = "宽" if axis == 0 else "高"
				_label(row, axis_label)
				var spin := SpinBox.new()
				spin.min_value = 0.0 if is_integer_vector else 0.01
				spin.max_value = 100000
				spin.step = 1.0 if is_integer_vector else 0.01
				spin.allow_greater = true
				spin.rounded = is_integer_vector
				spin.value_changed.connect(func(value: float):
					if is_integer_vector:
						var integer_vector: Vector2i = session.draft.get(key)
						integer_vector[axis] = int(value)
						_edit_field(key, integer_vector)
					else:
						var vector: Vector2 = session.draft.get(key)
						vector[axis] = value
						_edit_field(key, vector)
				)
				row.add_child(spin)
				editor = row
		elif info.type == TYPE_COLOR:
			var color_picker := ColorPickerButton.new()
			var editor_scale := EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
			color_picker.custom_minimum_size = Vector2(96, 32) * editor_scale
			color_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			color_picker.edit_alpha = true
			color_picker.color_changed.connect(func(next_color: Color): _edit_field(key, next_color))
			editor = color_picker
		elif info.type == TYPE_OBJECT:
			var picker := EditorResourcePicker.new()
			var base_type: String = str(info.hint_string)
			picker.base_type = base_type if not base_type.is_empty() else "Resource"
			picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			picker.resource_changed.connect(func(resource: Resource): _edit_field(key, resource))
			editor = picker
		elif info.hint == PROPERTY_HINT_ENUM:
			var option := OptionButton.new()
			var next_id := 0
			for entry in str(info.hint_string).split(","):
				var pair := entry.split(":")
				if pair.size() > 1:
					next_id = int(pair[1])
				option.add_item(pair[0], next_id)
				next_id += 1
			option.item_selected.connect(func(selected: int): _edit_field(key, option.get_item_id(selected)))
			editor = option
		else:
			var spin := SpinBox.new()
			spin.min_value = -100000
			spin.max_value = 100000
			spin.allow_greater = true
			spin.allow_lesser = true
			spin.step = 1.0 if info.type == TYPE_INT else 0.01
			if info.hint == PROPERTY_HINT_RANGE:
				var parts := str(info.hint_string).split(",")
				spin.min_value = float(parts[0])
				spin.max_value = float(parts[1])
				if parts.size() >= 3:
					spin.step = float(parts[2])
			spin.value_changed.connect(func(value: float):
				_edit_field(key, int(value) if info.type == TYPE_INT else (deg_to_rad(value) if key == "slot_start_angle" else value))
			)
			editor = spin
	field.add_child(editor)
	controls[key] = editor

func _sync_fields() -> void:
	for key in controls:
		var editor: Control = controls[key]
		if key == "_custom":
			editor.edit(session.draft if session.can_edit() else null)
			continue
		var value: Variant = session.draft.get(key)
		var reason: String = Catalog.disabled_reason(session.draft, key)
		var editable: bool = session.can_edit() and reason.is_empty()
		editor.tooltip_text = reason if not reason.is_empty() else Catalog.field_label(session.draft, key)
		if editor is CheckBox:
			editor.set_pressed_no_signal(value)
			editor.disabled = not editable
		elif editor is SpinBox:
			editor.set_value_no_signal(rad_to_deg(value) if key == "slot_start_angle" else value)
			editor.editable = editable
		elif editor is ColorPickerButton:
			if editor.color != value:
				editor.color = value
			editor.disabled = not editable
		elif editor is OptionButton:
			editor.select(editor.get_item_index(value))
			editor.disabled = not editable
		elif editor is EditorResourcePicker:
			editor.edited_resource = value
			editor.editable = editable
		elif editor is HBoxContainer:
			if value is Vector2 or value is Vector2i:
				for axis in 2:
					var spin: SpinBox = editor.get_child(axis * 2 + 1)
					spin.set_value_no_signal(value[axis])
					spin.editable = editable
			else:
				var path: LineEdit = editor.get_child(0)
				if path.text != value:
					path.text = value
				path.editable = editable
				editor.get_child(2).disabled = not editable

func _sync_detail() -> void:
	if not is_instance_valid(style_detail):
		return
	if session.draft == null or not Catalog.supports_detail_panel(session.draft):
		style_detail.visible = false
		style_inspector.edit(null)
		return
	style_detail.visible = true
	if not Catalog.is_detail_key(selected_detail_key, session.draft):
		selected_detail_key = Catalog.default_detail_key(session.draft)
	for key in detail_select_buttons:
		var button: Button = detail_select_buttons[key]
		button.set_pressed_no_signal(key == selected_detail_key)
		button.disabled = false
	if Catalog.is_material_key(selected_detail_key, session.draft):
		detail_title_label.text = "当前材质属性"
	else:
		detail_title_label.text = "当前样式属性"
	var resource: Resource = session.draft.get(selected_detail_key)
	var editable: bool = session.can_edit()
	var title: String = Catalog.field_label(session.draft, selected_detail_key)
	if resource == null:
		style_empty_label.text = "尚未配置%s；可新建或从资源选择器载入。" % title
		style_empty_label.visible = true
		style_create_row.visible = editable
		_rebuild_create_row()
		style_inspector.edit(null)
		style_inspector.visible = false
	else:
		style_empty_label.visible = false
		style_create_row.visible = false
		style_inspector.visible = true
		style_inspector.edit(resource if editable else null)

## 按当前嵌套键重建空值创建按钮。
func _rebuild_create_row() -> void:
	for child in style_create_row.get_children():
		style_create_row.remove_child(child)
		child.queue_free()
	if Catalog.is_material_key(selected_detail_key, session.draft):
		_button(style_create_row, "新建 ShaderMaterial", func(): _create_detail(ShaderMaterial.new()))
	else:
		_button(style_create_row, "新建 StyleBoxTexture", func(): _create_detail(StyleBoxTexture.new()))
		_button(style_create_row, "新建 StyleBoxFlat", func(): _create_detail(StyleBoxFlat.new()))

func _create_detail(resource: Resource) -> void:
	if session.can_edit() and Catalog.is_detail_key(selected_detail_key, session.draft):
		_edit_field(selected_detail_key, resource)

func _edit_field(key: String, value: Variant) -> void:
	if not _updating:
		session.set_field(key, value)
		if Catalog.is_detail_key(key, session.draft):
			selected_detail_key = key
			_sync_detail()

func _update_status() -> void:
	if not _built:
		return
	var reason: String = Catalog.validate(session.draft)
	if reason.is_empty():
		reason = _preview_problem
	if session.has_conflict():
		reason = "布局已被外部修改。请重新载入，避免覆盖外部改动。"
	status.text = reason if not reason.is_empty() else ("有未应用修改。" if session.is_dirty() else "布局已同步。")

func shutdown() -> void:
	if is_instance_valid(preview):
		preview.shutdown()
	if session != null and session.changed.is_connected(_session_changed):
		session.changed.disconnect(_session_changed)

func _exit_tree() -> void:
	shutdown()

func _clear_box(box: VBoxContainer) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()

func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button
