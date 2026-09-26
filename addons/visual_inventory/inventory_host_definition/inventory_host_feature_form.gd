@tool
extends VBoxContainer
## 小型资源表单，写入已授权编辑的草稿；领域适配决定字段和说明。
const Graph = preload("res://addons/visual_inventory/inventory_host_definition/host_editor_resource_graph.gd")
const INPUT_ACTION_TITLES := {
	InventoryInputActionIds.PRIMARY: "主交互（整组）",
	InventoryInputActionIds.PRIMARY_SINGLE: "主交互（单件）",
	InventoryInputActionIds.QUICK_TRANSFER: "快捷转移（整组）",
	InventoryInputActionIds.QUICK_TRANSFER_SINGLE: "快捷转移（单件）",
	InventoryInputActionIds.ROTATE: "旋转",
	InventoryInputActionIds.OPEN: "打开嵌套库存",
	InventoryInputActionIds.DESCRIBE: "主动查看描述",
}
signal rebuild_requested
var session: RefCounted
var index := -1
var resource: Resource
var controls: Dictionary = {}
var labels: Dictionary = {}
var declared_fields: Array[String] = []

func setup(value: RefCounted, entry_index: int) -> void:
	session = value
	index = entry_index
	resource = session.entries[index].draft
	add_theme_constant_override("separation", 8)

func add_note(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)

## 为领域控件复制资源草稿，保留图内别名与 Script、Texture2D、PackedScene 引用叶子。
func copy_resource(value: Resource) -> Resource:
	return Graph.copy(value)

func add_field(key: String, title: String) -> void:
	declared_fields.append(key)
	var info := _property(resource, key)
	if info.is_empty():
		add_note("字段不存在：" + key)
		return
	var editable: bool = session.feature_editable(index)
	var box := VBoxContainer.new()
	add_child(box)
	_label(box, title)
	controls[key] = _render(resource.get(key), info, func(value: Variant):
		if editable:
			resource.set(key, value)
			session.touch_feature(index)
	, box, 0, [resource])
	if not editable:
		_set_read_only(controls[key])

func add_feature_types(key: String, title: String) -> void:
	declared_fields.append(key)
	var editable: bool = session.feature_editable(index)
	add_note(title)
	var selected: Array = resource.get(key)
	var types: Array = []
	for entry in session.feature_catalog.entries:
		types.append(entry.type)
	for type in selected:
		if type not in types:
			types.append(type)
	for type in types:
		var info: Dictionary = session.feature_catalog.find(type) if type != null else {}
		var name_text: String = info.get("title", str(type.resource_path) if type != null else "空类型（取消勾选可删除）")
		var present := false
		for feature in session.feature_drafts():
			if feature != null and feature.get_script() == type:
				present = true
		var check := CheckBox.new()
		check.text = name_text + ("" if present else " · 当前父级未添加")
		check.set_pressed_no_signal(type in selected)
		check.disabled = not editable
		add_child(check)
		if editable:
			check.toggled.connect(func(enabled: bool):
				var next: Array = resource.get(key).duplicate()
				while next.has(type):
					next.erase(type)
				if enabled:
					next.append(type)
				resource.set(key, next)
				session.touch_feature(index)
			)
		controls[str(type)] = check

func add_input_actions(action_ids: Array, heading := "触发动作") -> void:
	if action_ids.is_empty():
		return
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	add_child(body)
	_label(body, heading)
	for action_value in action_ids:
		var action_id := StringName(action_value)
		var label := Label.new()
		label.text = "%s · %s · %s" % [INPUT_ACTION_TITLES.get(action_id, str(action_id)), action_id, _input_bindings(action_id)]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(label)
	controls["input_actions"] = body

func add_input_priority() -> void:
	add_field("input_priority", "输入优先级")

func _input_bindings(action_id: StringName) -> String:
	var events: Array = []
	var setting_path := "input/" + str(action_id)
	if ProjectSettings.has_setting(setting_path):
		var action_config: Dictionary = ProjectSettings.get_setting(setting_path, {})
		events = action_config.get("events", [])
	elif InputMap.has_action(action_id):
		events = InputMap.action_get_events(action_id)
	else:
		return "动作未注册"
	var bindings: Array[String] = []
	for event in events:
		if event is InputEvent:
			bindings.append(event.as_text())
	return "、".join(bindings) if not bindings.is_empty() else "未绑定"

func _set_read_only(control: Control) -> void:
	control.focus_mode = Control.FOCUS_NONE
	if control is BaseButton:
		(control as BaseButton).disabled = true
	elif control is LineEdit:
		(control as LineEdit).editable = false
	elif control is SpinBox:
		(control as SpinBox).editable = false
	elif control is EditorResourcePicker:
		(control as EditorResourcePicker).editable = false
	for child in control.get_children():
		if child is Control:
			_set_read_only(child)

func _property(object: Resource, key: String) -> Dictionary:
	for info in object.get_property_list():
		if str(info.name) == key:
			return info
	return {}

func _label(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)

func _render(value: Variant, info: Dictionary, setter: Callable, parent: Node, depth: int, ancestors: Array) -> Control:
	var kind: int = info.get("type", typeof(value))
	if kind == TYPE_BOOL:
		var control := CheckBox.new()
		control.set_pressed_no_signal(value)
		control.toggled.connect(setter)
		parent.add_child(control)
		return control
	if kind == TYPE_INT and info.get("hint", 0) == PROPERTY_HINT_ENUM:
		var control := OptionButton.new()
		var id := 0
		for entry in str(info.hint_string).split(","):
			var pair := entry.split(":")
			if pair.size() > 1:
				id = int(pair[1])
			control.add_item(pair[0], id)
			id += 1
		control.select(control.get_item_index(value))
		control.item_selected.connect(func(selected: int): setter.call(control.get_item_id(selected)))
		parent.add_child(control)
		return control
	if kind == TYPE_INT or kind == TYPE_FLOAT:
		var control := SpinBox.new()
		control.min_value = -100000
		control.max_value = 100000
		control.allow_greater = true
		control.allow_lesser = true
		control.step = 1 if kind == TYPE_INT else 0.01
		if info.get("hint", 0) == PROPERTY_HINT_RANGE:
			var parts := str(info.hint_string).split(",")
			control.min_value = float(parts[0])
			control.max_value = float(parts[1])
			if parts.size() > 2:
				control.step = float(parts[2])
		control.value = value
		control.value_changed.connect(func(next: float): setter.call(int(next) if kind == TYPE_INT else next))
		parent.add_child(control)
		return control
	var hint: int = int(info.get("hint", 0))
	if kind == TYPE_STRING and (hint == PROPERTY_HINT_FILE or hint == PROPERTY_HINT_GLOBAL_FILE):
		return _file_path_editor(str(value), info, setter, parent)
	if kind == TYPE_STRING or kind == TYPE_STRING_NAME or kind == TYPE_NODE_PATH:
		var control := LineEdit.new()
		control.text = str(value)
		control.text_changed.connect(func(next: String): setter.call(NodePath(next) if kind == TYPE_NODE_PATH else (StringName(next) if kind == TYPE_STRING_NAME else next)))
		parent.add_child(control)
		return control
	if kind == TYPE_COLOR:
		var control := ColorPickerButton.new()
		var editor_scale := EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
		control.custom_minimum_size = Vector2(96, 32) * editor_scale
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		control.color = value
		control.color_changed.connect(setter)
		parent.add_child(control)
		return control
	if kind in [TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I]:
		var row := HBoxContainer.new()
		parent.add_child(row)
		var state := {"value": value}
		var count := 2 if kind in [TYPE_VECTOR2, TYPE_VECTOR2I] else (3 if kind in [TYPE_VECTOR3, TYPE_VECTOR3I] else 4)
		for component in count:
			var scalar_type := TYPE_INT if kind in [TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I] else TYPE_FLOAT
			_render(value[component], {"type": scalar_type}, func(next: Variant):
				state.value[component] = next
				setter.call(state.value)
			, row, depth + 1, ancestors)
		return row
	if kind == TYPE_OBJECT:
		return _resource_editor(value, info, setter, parent, depth, ancestors)
	if kind == TYPE_ARRAY:
		var body := VBoxContainer.new()
		parent.add_child(body)
		if depth > 12:
			_label(body, "嵌套层级过深，保持原值。")
			return body
		for i in value.size():
			var element_info := {"type": value.get_typed_builtin() if value.is_typed() else typeof(value[i])}
			if element_info.type == TYPE_OBJECT:
				var type: Script = value.get_typed_script()
				element_info["hint_string"] = str(type.get_global_name()) if type != null else value.get_typed_class_name()
			var remove := func():
				var next: Array = value.duplicate()
				next.remove_at(i)
				setter.call(next)
				rebuild_requested.emit()
			# 资源条目：序号与删除都挂在资源选择行；其它类型用外层横排。
			if element_info.type == TYPE_OBJECT:
				element_info["array_index"] = i + 1
				element_info["array_remove"] = remove
				_render(value[i], element_info, func(next: Variant):
					value[i] = next
					setter.call(value)
				, body, depth + 1, ancestors)
			else:
				var row := HBoxContainer.new()
				body.add_child(row)
				_add_array_index_label(row, i + 1)
				var element := _render(value[i], element_info, func(next: Variant):
					value[i] = next
					setter.call(value)
				, row, depth + 1, ancestors)
				if element != null:
					element.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				_button(row, "删除", remove)
		_button(body, "＋ 添加条目", func():
			var next: Array = value.duplicate()
			var type: Script = value.get_typed_script()
			if type != null and type.can_instantiate() and not type.is_abstract():
				next.append(type.new())
			elif value.get_typed_builtin() == TYPE_STRING:
				next.append("")
			elif value.get_typed_builtin() == TYPE_STRING_NAME:
				next.append(&"")
			elif value.get_typed_builtin() == TYPE_INT:
				next.append(0)
			else:
				next.append(null)
			setter.call(next)
			rebuild_requested.emit()
		)
		return body
	var label := Label.new()
	label.text = "此类型只读：" + var_to_str(value)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _resource_editor(value: Resource, info: Dictionary, setter: Callable, parent: Node, depth: int, ancestors: Array) -> Control:
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
	# 资源选择和嵌套字段编辑通过当前表单提交草稿。
	_add_resource_header_action(row, base_type, setter, info)
	if value != null and not Graph.leaf(value):
		if depth > 12 or value in ancestors:
			_label(body, "循环引用／深层资源保留，避免重复展开。")
			return body
		var children := VBoxContainer.new()
		body.add_child(children)
		var next_ancestors := ancestors.duplicate()
		next_ancestors.append(value)
		for property in value.get_property_list():
			if property.usage & PROPERTY_USAGE_EDITOR and property.usage & PROPERTY_USAGE_STORAGE and property.name not in ["script", "resource_name", "resource_local_to_scene"]:
				var key: String = property.name
				_label(children, labels.get(key, key))
				_render(value.get(key), property, func(next: Variant):
					value.set(key, next)
					setter.call(value)
				, children, depth + 1, next_ancestors)
	return body

func _choose_resource(base_type: String, setter: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "新建 " + base_type
	dialog.dialog_text = "选择具体配置类型"
	var options := OptionButton.new()
	dialog.add_child(options)
	var types: Array = []
	for info in ProjectSettings.get_global_class_list():
		var current: String = info.class
		var candidate: Script = null
		while not current.is_empty():
			if current == base_type or base_type == "Resource":
				candidate = load(info.path)
				break
			var next := ""
			for parent in ProjectSettings.get_global_class_list():
				if parent.class == current:
					next = parent.base
					break
			current = next
		if candidate != null and candidate.get_instance_base_type() == "Resource" and not candidate.is_abstract():
			options.add_item(str(info.class))
			types.append(candidate)
	if types.is_empty() and ClassDB.can_instantiate(base_type) and ClassDB.is_parent_class(base_type, "Resource"):
		options.add_item(base_type)
		types.append(base_type)
	dialog.get_ok_button().disabled = types.is_empty()
	if not types.is_empty():
		options.select(0)
	add_child(dialog)
	dialog.confirmed.connect(func():
		if options.selected < 0 or options.selected >= types.size():
			return
		var type: Variant = types[options.selected]
		setter.call(type.new() if type is Script else ClassDB.instantiate(type))
		dialog.queue_free()
		rebuild_requested.emit()
	)
	dialog.canceled.connect(dialog.queue_free)
	if DisplayServer.get_name() == "headless":
		dialog.popup(Rect2i(Vector2i.ZERO, Vector2i(440, 180)))
	else:
		dialog.popup_centered(Vector2i(440, 180))

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


## 资源选择行右侧动作：数组条目用删除，其它字段用新建。
func _add_resource_header_action(row: Node, base_type: String, setter: Callable, info: Dictionary) -> void:
	if info.has("array_remove"):
		_button(row, "删除", info.array_remove)
		return
	if base_type not in ["Script", "Texture2D", "Texture"]:
		_button(row, "新建", func(): _choose_resource(base_type, setter))


## 数组序号：贴在资源选择器左侧，固定宽度便于对齐。
func _add_array_index_label(parent: Node, index: int) -> void:
	if index < 1:
		return
	var label := Label.new()
	label.text = str(index)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var editor_scale := EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
	label.custom_minimum_size.x = 28.0 * editor_scale
	parent.add_child(label)


## 路径字符串字段：输入框旁提供与 Inspector @export_file 一致的打开文件按钮。
func _file_path_editor(value: String, info: Dictionary, setter: Callable, parent: Node) -> Control:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var edit := LineEdit.new()
	edit.text = value
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_changed.connect(func(next: String): setter.call(next))
	row.add_child(edit)
	var browse := Button.new()
	browse.tooltip_text = "打开文件"
	if Engine.is_editor_hint():
		browse.icon = EditorInterface.get_base_control().get_theme_icon("Folder", "EditorIcons")
	else:
		browse.text = "打开文件"
	browse.pressed.connect(func(): _pick_file_path(edit, info, setter))
	row.add_child(browse)
	return row


## 弹出资源文件对话框，确认后写回路径字符串。
func _pick_file_path(edit: LineEdit, info: Dictionary, setter: Callable) -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	dialog.access = (
		EditorFileDialog.ACCESS_FILESYSTEM
		if info.get("hint", 0) == PROPERTY_HINT_GLOBAL_FILE
		else EditorFileDialog.ACCESS_RESOURCES
	)
	for entry in str(info.get("hint_string", "")).split(","):
		var filter := entry.strip_edges()
		if not filter.is_empty():
			dialog.add_filter(filter)
	var current := _resolve_resource_path(edit.text.strip_edges())
	if current.begins_with("res://") or current.begins_with("user://"):
		dialog.current_dir = current.get_base_dir()
		dialog.current_file = current.get_file()
	dialog.file_selected.connect(func(path: String):
		edit.text = path
		setter.call(path)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.6)


## 将 uid:// 解析为 res://，供文件对话框定位当前目录。
func _resolve_resource_path(path_or_uid: String) -> String:
	if path_or_uid.is_empty() or not path_or_uid.begins_with("uid://"):
		return path_or_uid
	var uid := ResourceUID.text_to_id(path_or_uid)
	if uid == ResourceUID.INVALID_ID:
		return path_or_uid
	var resolved := ResourceUID.get_id_path(uid)
	return resolved if not resolved.is_empty() else path_or_uid
