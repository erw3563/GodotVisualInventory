@tool
extends "res://addons/visual_inventory/inventory_host_definition/inventory_host_feature_form.gd"
## 复用已有草稿资源表单；补齐物品的多行文案、PackedArray 字段与字符串集合勾选。
var _field_choices: Dictionary = {}


## 登记字段候选元数据（键为字段名，值为候选字典），由面板传入、领域适配读取。
func set_field_choices(key: String, choices: Dictionary) -> void:
	_field_choices[key] = choices.duplicate()


## 取回字段候选元数据；未登记的字段返回空字典。
func get_field_choices(key: String) -> Dictionary:
	return _field_choices.get(key, {})


## 为字符串集合字段构建勾选与自定义输入控件：候选按传入顺序展示，
## 当前值中未登记的候选以自身为显示名并入；勾选、取消与添加统一走
## 去重与空值过滤，写入已授权草稿字段并触发变更与重建。
func add_string_choices(key: String, title: String, choices: Dictionary) -> void:
	declared_fields.append(key)
	_label(self, title)
	var editable: bool = session.feature_editable(index)
	var current: PackedStringArray = resource.get(key)
	var candidates := choices.duplicate()
	for value in current:
		if not candidates.has(value):
			candidates[value] = value
	for value in candidates:
		var check := CheckBox.new()
		check.text = candidates[value]
		check.tooltip_text = value
		check.set_pressed_no_signal(value in current)
		check.disabled = not editable
		if editable:
			check.toggled.connect(func(enabled: bool): _toggle_string_member(key, value, enabled))
		add_child(check)
		controls[key + ":" + value] = check
	var row := HBoxContainer.new()
	add_child(row)
	var input := LineEdit.new()
	input.placeholder_text = "自定义" + title
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.editable = editable
	row.add_child(input)
	var add_button := _button(row, "添加", func(): _toggle_string_member(key, input.text, true))
	add_button.disabled = not editable
	controls[key] = row


## 按会话语义写入单个字符串成员：去除首尾空白、拒绝空值、清掉全部重复后按需追加。
func _toggle_string_member(key: String, value: String, enabled: bool) -> void:
	value = value.strip_edges()
	if value.is_empty():
		return
	var strings: Array = Array(resource.get(key))
	while strings.has(value):
		strings.erase(value)
	if enabled:
		strings.append(value)
	if typeof(resource.get(key)) == TYPE_PACKED_STRING_ARRAY:
		resource.set(key, PackedStringArray(strings))
	else:
		resource.set(key, strings)
	session.touch_feature(index)
	rebuild_requested.emit()

func _render(value: Variant, info: Dictionary, setter: Callable, parent: Node, depth: int, ancestors: Array) -> Control:
	var kind: int = info.get("type", typeof(value))
	if kind == TYPE_STRING and info.get("hint", 0) == PROPERTY_HINT_MULTILINE_TEXT:
		var control := TextEdit.new()
		control.text = value
		control.custom_minimum_size.y = 90
		control.text_changed.connect(func(): setter.call(control.text))
		parent.add_child(control)
		return control
	if kind in [TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY]:
		var body := VBoxContainer.new()
		parent.add_child(body)
		for i in value.size():
			var row := HBoxContainer.new()
			body.add_child(row)
			_render(value[i], {"type": typeof(value[i])}, func(next: Variant):
				value[i] = next
				setter.call(value)
			, row, depth + 1, ancestors)
			_button(row, "移除", func():
				var next: Variant = value.duplicate()
				next.remove_at(i)
				setter.call(next)
				rebuild_requested.emit()
			)
		_button(body, "＋ 添加条目", func():
			var next: Variant = value.duplicate()
			match kind:
				TYPE_PACKED_STRING_ARRAY: next.append("")
				TYPE_PACKED_VECTOR2_ARRAY: next.append(Vector2.ZERO)
				TYPE_PACKED_VECTOR3_ARRAY: next.append(Vector3.ZERO)
				TYPE_PACKED_COLOR_ARRAY: next.append(Color.WHITE)
				_: next.append(0)
			setter.call(next)
			rebuild_requested.emit()
		)
		return body
	return super._render(value, info, setter, parent, depth, ancestors)

func _resource_editor(value: Resource, info: Dictionary, setter: Callable, parent: Node, depth: int, ancestors: Array) -> Control:
	if value is InventoryData or value is OccupyMap:
		return _occupy_map_resource_editor(value, info, setter, parent, depth, ancestors)
	var body := super._resource_editor(value, info, setter, parent, depth, ancestors)
	if value is Shape and value not in ancestors and depth <= 12:
		var editor: Control = preload("res://addons/visual_inventory/shape/visual_shape_res_editor_panel.tscn").instantiate()
		body.add_child(editor)
		editor.set_shape_resource(value)
		editor.set_cells(value.cells)
		editor.pop_button.hide()
		editor.cells_changed.connect(func(cells: Array[Vector2i]):
			value.cells = cells.duplicate()
			setter.call(value)
		)
		controls["shape_canvas"] = editor
	return body


## InventoryData / OccupyMap：资源选择 + OccupyMap 画布，不展开通用属性列表。
func _occupy_map_resource_editor(
	value: Resource,
	info: Dictionary,
	setter: Callable,
	parent: Node,
	depth: int,
	ancestors: Array
) -> Control:
	var body := VBoxContainer.new()
	parent.add_child(body)
	var row := HBoxContainer.new()
	body.add_child(row)
	_add_array_index_label(row, info.get("array_index", 0))
	var picker := EditorResourcePicker.new()
	var base_type: String = info.get("hint_string", "Resource")
	if base_type.is_empty():
		base_type = "Resource"
	picker.base_type = base_type
	picker.edited_resource = value
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(picker)
	picker.resource_changed.connect(func(next: Resource):
		setter.call(Graph.copy(next))
		rebuild_requested.emit()
	)
	_add_resource_header_action(row, base_type, setter, info)
	if value == null or depth > 12 or value in ancestors:
		return body
	var occupy_map: OccupyMap = value as OccupyMap
	if value is InventoryData:
		var inventory := value as InventoryData
		if inventory.occupy_map == null:
			inventory.occupy_map = ShapeInventoryOccupyMap.new()
			inventory.occupy_map.init_region_by_size(InventoryData.DEFAULT_OCCUPY_MAP_SIZE)
			setter.call(inventory)
		occupy_map = inventory.occupy_map
	if occupy_map == null:
		return body
	var editor: Control = preload(
		"res://addons/visual_inventory/occupy/visual_occupy_map_res_editor_panel.tscn"
	).instantiate()
	body.add_child(editor)
	editor.set_occupy_map_resource(occupy_map)
	editor.set_cells(occupy_map.cells)
	editor.pop_button.hide()
	editor.cells_changed.connect(func(cells: Array[Vector2i]):
		occupy_map.cells = cells.duplicate()
		setter.call(value)
	)
	controls["occupy_map_canvas"] = editor
	return body
