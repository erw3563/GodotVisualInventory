@tool
extends VBoxContainer
## 编辑当前外观样式，变更通过所属草稿回调提交。
const Types = preload("res://addons/visual_res_editor_panel/gdbase/inventory/parts/cell_appearance/editor/inventory_visual_style_editor_catalog.gd")
signal changed
var style: InventoryItemVisualStyle
var writable := true
var can_write: Callable
var controls := {}
var editor_scale := 1.0

func setup(value: InventoryItemVisualStyle, permission: Callable, scale_override := 0.0) -> void:
	style = value
	can_write = permission
	writable = can_write.call()
	editor_scale = scale_override if scale_override > 0 else (EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0)
	add_theme_constant_override("separation", 8)
	_toggle("use_border", "绘制边框")
	_color("border_color", "边框颜色")
	_toggle("use_fill", "绘制填充")
	_color("fill_color", "填充颜色")
	var type_index := Types.index_of(style)
	if type_index >= 0:
		Types.TYPES[type_index].editor.build(self)

func build_line_width() -> void:
	var global_width := CheckBox.new()
	global_width.text = "使用背包默认线宽"
	global_width.set_pressed_no_signal(float(style.get("border_width")) <= 0)
	global_width.disabled = not writable
	add_child(global_width)
	controls["global_width"] = global_width
	var width := SpinBox.new()
	width.min_value = 0.1
	width.max_value = 100
	width.allow_greater = true
	width.step = 0.1
	width.value = float(style.get("border_width")) if float(style.get("border_width")) > 0 else 3.0
	width.editable = writable and float(style.get("border_width")) > 0
	width.suffix = "像素"
	add_child(width)
	controls["border_width"] = width
	global_width.toggled.connect(func(enabled: bool):
		if not can_write.call():
			return
		width.editable = not enabled
		style.set("border_width", -1.0 if enabled else maxf(0.1, width.value))
		changed.emit()
	)
	width.value_changed.connect(func(value_width: float):
		if can_write.call() and not global_width.button_pressed and is_finite(value_width):
			style.set("border_width", value_width)
			changed.emit()
	)

func _toggle(key: String, title: String) -> void:
	var control := CheckBox.new()
	control.text = title
	control.disabled = not writable
	control.set_pressed_no_signal(style.get(key))
	control.toggled.connect(func(value: bool):
		if can_write.call():
			style.set(key, value)
			changed.emit()
	)
	add_child(control)
	controls[key] = control

func _color(key: String, title: String) -> void:
	var heading := Label.new()
	heading.text = title
	add_child(heading)
	var row := HFlowContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(row)
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(96, 32) * editor_scale
	picker.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	picker.color = style.get(key)
	picker.disabled = not writable
	row.add_child(picker)
	var hex := LineEdit.new()
	hex.custom_minimum_size.x = 120 * editor_scale
	hex.placeholder_text = "#RRGGBBAA"
	hex.editable = writable
	row.add_child(hex)
	var alpha := SpinBox.new()
	alpha.min_value = 0
	alpha.max_value = 1
	alpha.allow_greater = true
	alpha.allow_lesser = true
	alpha.step = 0.01
	alpha.prefix = "Alpha"
	alpha.editable = writable
	row.add_child(alpha)
	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(note)
	controls[key] = picker
	controls[key + "_hex"] = hex
	controls[key + "_alpha"] = alpha
	var sync := func():
		var color: Color = style.get(key)
		picker.color = color
		alpha.set_value_no_signal(color.a)
		var in_range := color.r >= 0 and color.r <= 1 and color.g >= 0 and color.g <= 1 and color.b >= 0 and color.b <= 1 and color.a >= 0 and color.a <= 1
		hex.text = "#" + color.to_html(true) if in_range else ""
		note.text = "" if in_range else "当前使用浮点颜色；提交 HEX 将采用对应的 0～1 颜色值。"
	sync.call()
	picker.color_changed.connect(func(value: Color):
		if can_write.call():
			style.set(key, value)
			sync.call()
			changed.emit()
	)
	hex.text_submitted.connect(func(text: String):
		if not can_write.call():
			return
		if not Color.html_is_valid(text):
			note.text = "请输入有效的 HEX 颜色。"
			return
		style.set(key, Color.html(text))
		sync.call()
		changed.emit()
	)
	alpha.value_changed.connect(func(value: float):
		if can_write.call() and is_finite(value):
			var color: Color = style.get(key)
			color.a = value
			style.set(key, color)
			sync.call()
			changed.emit()
	)

func build_texture(key: String, title: String) -> void:
	var label := Label.new()
	label.text = title
	add_child(label)
	var picker := EditorResourcePicker.new()
	picker.base_type = "Texture2D"
	picker.edited_resource = style.get(key)
	picker.editable = writable
	add_child(picker)
	controls[key] = picker
	picker.resource_changed.connect(func(value: Resource):
		if can_write.call():
			style.set(key, value)
			changed.emit()
	)

func build_margins() -> void:
	var label := Label.new()
	label.text = "框边距（左／上／右／下）"
	add_child(label)
	var row := HFlowContainer.new()
	add_child(row)
	var margins: Vector4i = style.get("frame_border_margins")
	var fields: Array[SpinBox] = []
	for index in 4:
		var field := SpinBox.new()
		field.min_value = 0
		field.max_value = 4096
		field.allow_greater = true
		field.step = 1
		field.value = margins[index]
		field.editable = writable
		field.custom_minimum_size.x = 80 * editor_scale
		row.add_child(field)
		fields.append(field)
		field.value_changed.connect(func(value: float):
			if can_write.call():
				var current: Vector4i = style.get("frame_border_margins")
				current[index] = int(value)
				style.set("frame_border_margins", current)
				changed.emit()
		)
	controls["frame_border_margins"] = fields
