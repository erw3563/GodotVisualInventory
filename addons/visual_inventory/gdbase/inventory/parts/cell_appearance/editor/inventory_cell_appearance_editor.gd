@tool
extends VBoxContainer
## 外观键专用编辑页，操作所属会话的草稿资源。
const Catalog = preload("res://addons/visual_inventory/gdbase/inventory/parts/cell_appearance/editor/inventory_appearance_key_catalog.gd")
const KeyEntry = preload("res://addons/visual_inventory/gdbase/inventory/parts/cell_appearance/editor/inventory_appearance_key_entry.gd")
const Store = preload("res://addons/visual_inventory/gdbase/inventory/parts/cell_appearance/editor/inventory_appearance_key_catalog_store.gd")
const Picker = preload("res://addons/visual_inventory/gdbase/inventory/parts/cell_appearance/editor/inventory_appearance_key_picker.gd")
const StyleEditor = preload("res://addons/visual_inventory/gdbase/inventory/parts/cell_appearance/editor/inventory_item_visual_style_editor.gd")
const Preview = preload("res://addons/visual_inventory/gdbase/inventory/parts/cell_appearance/editor/inventory_cell_appearance_preview.gd")
const BASIC_STYLES := "res://addons/visual_inventory/gdbase/inventory/parts/cell_appearance/presets/default_cell_appearance_part.tres"
const Types = preload("res://addons/visual_inventory/gdbase/inventory/parts/cell_appearance/editor/inventory_visual_style_editor_catalog.gd")
var style_type_picker: OptionButton
var style_problem: Label
var form: Control
var host_mode := false
var store: RefCounted
var state: Dictionary
var picker: Button
var details: VBoxContainer
var message: Label
var library_status: Label
var source_picker: EditorResourcePicker
var style_editor: Control
var preview: Control
var save_button: Button
var create_library_button: Button
var _queued := false

func setup(owner_form: Control, is_host: bool, library: RefCounted = null) -> void:
	form = owner_form
	host_mode = is_host
	store = library if library != null else Store.shared()
	var states: Dictionary = form.session.get_meta("appearance_views", {})
	var token := str(form.resource.get_instance_id())
	if not states.has(token):
		states[token] = {"key": &"", "pending": {}, "known_keys": [], "search": "", "shape": 0, "light": false, "zoom": 1.0, "types": {}}
	form.session.set_meta("appearance_views", states)
	state = states[token]
	if not state.has("types"):
		state.types = {}

func _ready() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if host_mode:
		_label(self, "默认外观资源")
		source_picker = EditorResourcePicker.new()
		source_picker.base_type = "ItemCellAppearancePart"
		source_picker.edited_resource = part()
		source_picker.editable = can_edit()
		add_child(source_picker)
		source_picker.resource_changed.connect(func(value: Resource):
			if can_edit():
				state.types.clear()
				form.resource.default_cell_appearance_part = form.copy_resource(value)
				_touch()
				request_rebuild()
		)
		var source_actions := HFlowContainer.new()
		add_child(source_actions)
		_button(source_actions, "新建默认外观", func():
			if can_edit():
				state.types.clear()
				form.resource.default_cell_appearance_part = ItemCellAppearancePart.new()
				_touch()
				request_rebuild()
		)
		_button(source_actions, "复制默认外观为独有", func():
			if can_edit() and part() != null:
				state.types.clear()
				form.resource.default_cell_appearance_part = form.copy_resource(part())
				_touch()
				request_rebuild()
		)
	_label(self, "外观键")
	picker = Picker.new()
	picker.search_text = state.search
	picker.search_changed.connect(func(value: String): state.search = value)
	picker.key_selected.connect(select_key)
	picker.opening.connect(func(): store.refresh_if_changed())
	add_child(picker)
	var actions := HFlowContainer.new()
	add_child(actions)
	_button(actions, "新增特殊键", func(): open_key_dialog("new"))
	save_button = _button(actions, "保存到键库", save_selected_key)
	_button(actions, "补齐基础样式", complete_basics)
	create_library_button = _button(actions, "创建键库", func():
		var reason: String = store.create_catalog()
		message.text = reason if not reason.is_empty() else "键库已创建：" + store.path
	)
	library_status = _label(self, "")
	message = _label(self, "")
	_label(self, "保存到键库会保存键名与用途；样式通过当前窗口的应用与保存操作提交。")
	details = VBoxContainer.new()
	details.add_theme_constant_override("separation", 8)
	add_child(details)
	store.changed.connect(_refresh_picker)
	form.session.changed.connect(_session_changed)
	if store.catalog == null:
		store.reload()
	_refresh_picker()
	_rebuild()

func part() -> ItemCellAppearancePart:
	return form.resource.default_cell_appearance_part if host_mode else form.resource as ItemCellAppearancePart

func can_edit() -> bool:
	return is_instance_valid(form) and form.session.feature_editable(form.index)

func selected_entry() -> InventoryCellAppearanceEntry:
	var value := part()
	if value != null:
		for entry in value.appearances:
			if entry != null and entry.id == state.key:
				return entry
	return null

func select_key(key: StringName) -> void:
	state.key = key
	message.text = ""
	_refresh_picker()
	request_rebuild()

func _metadata(key: StringName) -> InventoryAppearanceKeyEntry:
	if state.pending.has(key):
		return state.pending[key]
	var registered: InventoryAppearanceKeyEntry = store.catalog.find(key)
	if registered != null:
		return registered
	var result := KeyEntry.new()
	result.id = key
	result.display_name = str(key)
	return result

func _refresh_picker() -> void:
	if not is_instance_valid(picker) or store.catalog == null:
		return
	var keys: Array[StringName] = Catalog.BASIC_KEYS.duplicate()
	for metadata in store.catalog.entries:
		if metadata.id not in keys:
			keys.append(metadata.id)
	for key in state.pending:
		if key not in keys:
			keys.append(key)
	for key in state.known_keys:
		if key not in keys:
			keys.append(key)
	var counts := {}
	var value := part()
	if value != null:
		for entry in value.appearances:
			if entry != null and entry.id != &"":
				if entry.id not in state.known_keys:
					state.known_keys.append(entry.id)
				counts[entry.id] = counts.get(entry.id, 0) + 1
				if entry.id not in keys:
					keys.append(entry.id)
	if state.key == &"" or state.key not in keys:
		state.key = &"placed"
		if not counts.has(&"placed") and value != null:
			for entry in value.appearances:
				if entry != null and entry.id != &"":
					state.key = entry.id
					break
	var choices: Array[Dictionary] = []
	for key in keys:
		var metadata := _metadata(key)
		var configured: InventoryCellAppearanceEntry
		if value != null:
			for entry in value.appearances:
				if entry != null and entry.id == key:
					configured = entry
					break
		var status := "未配置"
		if counts.has(key):
			status = "已配置" if counts[key] == 1 and configured.style != null and configured.style.validate_configuration().is_empty() else "配置异常"
		var icon: Texture2D
		if configured != null and configured.style != null:
			icon = _swatch(configured.style)
		choices.append({"id": key, "title": metadata.display_name, "description": metadata.description, "status": status, "icon": icon})
	picker.set_candidates(choices, state.key)
	library_status.text = store.problem if not store.problem.is_empty() else ("键库：" + store.path)
	var saved: bool = store.catalog.find(state.key) != null and not state.pending.has(state.key)
	save_button.disabled = not can_edit() or not store.problem.is_empty() or saved
	create_library_button.visible = not FileAccess.file_exists(store.path)
	create_library_button.disabled = not can_edit()

func _swatch(value: InventoryItemVisualStyle) -> Texture2D:
	var image := Image.create(28, 14, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.3, 0.3, 0.3))
	for y in 14:
		for x in 28:
			var background := Color(0.6, 0.6, 0.6) if (x / 4 + y / 4) % 2 == 0 else Color(0.3, 0.3, 0.3)
			var color := value.border_color if x < 14 else value.fill_color
			var enabled := value.use_border if x < 14 else value.use_fill
			image.set_pixel(x, y, background.blend(color) if enabled else background)
	return ImageTexture.create_from_image(image)

func request_rebuild() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	_rebuild.call_deferred()

func _rebuild() -> void:
	_queued = false
	for child in details.get_children():
		details.remove_child(child)
		child.queue_free()
	style_editor = null
	style_problem = null
	preview = null
	if source_picker != null:
		source_picker.edited_resource = part()
	var metadata := _metadata(state.key)
	_label(details, metadata.display_name + " · " + str(state.key) + "\n" + metadata.description)
	if store.catalog.find(state.key) == null:
		_label(details, "尚未保存到公共键库")
	_build_anomalies()
	var entry := selected_entry()
	if entry == null:
		_label(details, "当前外观键尚未配置。")
		_button(details, "为此键创建样式", func(): create_style(state.key))
		return
	var actions := HFlowContainer.new()
	details.add_child(actions)
	_button(actions, "移除本键配置", func(): remove_entry(part().appearances.find(entry)))
	_button(actions, "更换本条目键", func(): open_key_dialog("rename"))
	var resource_picker := EditorResourcePicker.new()
	resource_picker.base_type = "InventoryItemVisualStyle"
	resource_picker.edited_resource = entry.style
	resource_picker.editable = can_edit()
	details.add_child(resource_picker)
	resource_picker.resource_changed.connect(func(value: Resource):
		if can_edit():
			state.types.erase(entry.get_instance_id())
			entry.style = form.copy_resource(value)
			_touch()
			request_rebuild()
	)
	if entry.style == null:
		_button(details, "创建缺失样式", func(): create_style(state.key))
		return
	var aliases: Array[String] = []
	for other in part().appearances:
		if other != null and other.style == entry.style:
			aliases.append(str(other.id))
	var original: Resource = form.session.reverse.get(entry.style, entry.style)
	_label(details, "共用此样式的键：" + "、".join(aliases) + ("\n共享资源：" + original.resource_path if not original.resource_path.is_empty() else ""))
	_button(details, "复制为当前键独有", make_style_unique)
	_button(details, "复制样式到其他键", func(): open_key_dialog("copy"))
	_label(details, "样式类型")
	style_type_picker = OptionButton.new()
	for type in Types.TYPES:
		style_type_picker.add_item(type.title)
	style_type_picker.select(Types.index_of(entry.style))
	style_type_picker.disabled = not can_edit()
	details.add_child(style_type_picker)
	style_type_picker.item_selected.connect(switch_style_type)
	style_problem = _label(details, "")
	_update_style_problem()
	style_editor = StyleEditor.new()
	style_editor.name = "CurrentStyle"
	style_editor.setup(entry.style, can_edit)
	style_editor.changed.connect(_touch)
	details.add_child(style_editor)
	var preview_options := HFlowContainer.new()
	details.add_child(preview_options)
	var shape := OptionButton.new()
	for title in ["单格", "2×2", "L 形"]:
		shape.add_item(title)
	shape.select(state.shape)
	preview_options.add_child(shape)
	var background := CheckBox.new()
	background.text = "浅色背景"
	background.set_pressed_no_signal(state.light)
	preview_options.add_child(background)
	var zoom_control := SpinBox.new()
	zoom_control.min_value = 0.5
	zoom_control.max_value = 2.0
	zoom_control.step = 0.25
	zoom_control.value = state.zoom
	zoom_control.suffix = "倍"
	preview_options.add_child(zoom_control)
	_label(details, "当前键静态预览：" + str(state.key) + ("\n默认线宽来自此背包。" if host_mode else "\n示例参数：格子 48，默认线宽 3。"))
	preview = Preview.new()
	preview.shape_index = state.shape
	preview.light_background = state.light
	preview.zoom = state.zoom
	details.add_child(preview)
	preview.set_style(entry.style, form.resource if host_mode else null)
	shape.item_selected.connect(func(index: int):
		state.shape = index
		preview.shape_index = index
		preview.request_refresh()
	)
	background.toggled.connect(func(enabled: bool):
		state.light = enabled
		preview.light_background = enabled
		preview.request_refresh()
	)
	zoom_control.value_changed.connect(func(value: float):
		state.zoom = value
		preview.zoom = value
		preview.request_refresh()
	)
	_label(details, "贴图模式的边框厚度由框贴图边距决定；样式线宽用于线条模式。")

func _build_anomalies() -> void:
	var value := part()
	if value == null:
		return
	var seen := {}
	for index in value.appearances.size():
		var entry := value.appearances[index]
		var reason := ""
		if entry == null:
			reason = "空条目"
		elif entry.id == &"":
			reason = "空外观键"
		elif seen.has(entry.id):
			reason = "重复外观键：" + str(entry.id)
		elif entry.style == null:
			reason = "缺少样式：" + str(entry.id)
		if entry != null:
			seen[entry.id] = true
		if reason.is_empty():
			continue
		var row := HFlowContainer.new()
		details.add_child(row)
		_label(row, "条目 %d：%s" % [index + 1, reason])
		_button(row, "修复", func(): open_key_dialog("repair", index))
		_button(row, "删除", func(): remove_entry(index))

func create_style(key: StringName, copied_style: InventoryItemVisualStyle = null) -> String:
	if not can_edit():
		return "当前资源为只读。"
	if key == &"":
		return "请选择外观键。"
	var value := part()
	if value == null:
		if not host_mode:
			return "外观 Part 缺失。"
		value = ItemCellAppearancePart.new()
		form.resource.default_cell_appearance_part = value
	var entry: InventoryCellAppearanceEntry
	for existing in value.appearances:
		if existing != null and existing.id == key:
			entry = existing
			break
	if entry != null and entry.style != null:
		return "此键已配置。"
	if entry == null:
		entry = InventoryCellAppearanceEntry.new()
		entry.id = key
		value.appearances.append(entry)
	entry.style = _new_style(key, copied_style)
	state.key = key
	_touch()
	request_rebuild()
	return ""

func _new_style(key: StringName, copied_style: InventoryItemVisualStyle = null) -> InventoryItemVisualStyle:
	if copied_style != null:
		return form.copy_resource(copied_style)
	if key in Catalog.BASIC_KEYS:
		var defaults := load(BASIC_STYLES) as ItemCellAppearancePart
		return form.copy_resource(defaults.resolve_style(key))
	return InventoryItemLineVisualStyle.new()

func complete_basics() -> void:
	if not can_edit():
		return
	if part() != null and not part().validate_appearances().is_empty():
		message.text = "请先修复外观条目：" + str(part().validate_appearances())
		return
	var previous: StringName = state.key
	for key in Catalog.BASIC_KEYS:
		create_style(key)
	state.key = previous
	_refresh_picker()
	request_rebuild()

func remove_entry(index: int) -> void:
	if can_edit() and part() != null and index >= 0 and index < part().appearances.size():
		var entry := part().appearances[index]
		if entry != null:
			state.types.erase(entry.get_instance_id())
		part().appearances.remove_at(index)
		_touch()
		request_rebuild()

func make_style_unique() -> void:
	var entry := selected_entry()
	if can_edit() and entry != null and entry.style != null:
		state.types.erase(entry.get_instance_id())
		entry.style = form.copy_resource(entry.style)
		_touch()
		request_rebuild()

func rename_entry(index: int, key: StringName) -> String:
	if not can_edit() or part() == null or index < 0 or index >= part().appearances.size():
		return "请选择有效条目。"
	var reason := Catalog.validate_key(str(key))
	if not reason.is_empty():
		return reason
	for other_index in part().appearances.size():
		var other := part().appearances[other_index]
		if other_index != index and other != null and other.id == key:
			return "当前物品框已配置此键。"
	var entry := part().appearances[index]
	if entry == null:
		entry = InventoryCellAppearanceEntry.new()
		part().appearances[index] = entry
	entry.id = key
	if entry.style == null:
		entry.style = _new_style(key)
	state.key = key
	_touch()
	request_rebuild()
	return ""

func save_selected_key() -> void:
	if not can_edit():
		return
	if not state.pending.has(state.key):
		open_key_dialog("save")
		return
	var reason: String = store.save_entry(state.pending[state.key])
	if reason.is_empty():
		state.pending.erase(state.key)
	message.text = reason if not reason.is_empty() else "已保存到键库：" + store.path
	_refresh_picker()

func open_key_dialog(mode: String, repair_index := -1) -> void:
	if not can_edit():
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = {"new": "新增特殊键", "save": "保存外观键到键库", "rename": "更换本条目键", "repair": "修复外观条目", "copy": "复制样式到其他键"}[mode]
	dialog.exclusive = true
	dialog.dialog_hide_on_ok = false
	var source_entry := selected_entry()
	var entry_index := repair_index
	if mode == "rename":
		entry_index = part().appearances.find(source_entry)
	var body := VBoxContainer.new()
	dialog.add_child(body)
	_label(body, "外观键")
	var key_input := LineEdit.new()
	key_input.custom_minimum_size.x = 320
	key_input.text = str(state.key) if mode == "save" else ""
	key_input.editable = mode != "save"
	body.add_child(key_input)
	if mode in ["rename", "repair", "copy"]:
		var available: Array[Dictionary] = []
		for candidate in picker.candidates:
			var occupied := false
			for index in part().appearances.size():
				var entry := part().appearances[index]
				if entry != null and entry.id == candidate.id and (mode == "copy" or index != entry_index):
					occupied = true
			if not occupied:
				available.append(candidate)
		var choice := Picker.new()
		choice.set_candidates(available, &"")
		choice.text = "从可用外观键选择…"
		choice.key_selected.connect(func(key: StringName): key_input.text = str(key))
		body.add_child(choice)
	var metadata := _metadata(state.key)
	var title_label := _label(body, "显示名称")
	var title_input := LineEdit.new()
	title_input.text = metadata.display_name if mode == "save" else ""
	body.add_child(title_input)
	var description_label := _label(body, "用途说明")
	var description_input := LineEdit.new()
	description_input.text = metadata.description if mode == "save" else ""
	body.add_child(description_input)
	var copy_style := CheckBox.new()
	copy_style.text = "复制当前键样式"
	copy_style.visible = mode == "new"
	copy_style.disabled = selected_entry() == null or selected_entry().style == null
	body.add_child(copy_style)
	var error := _label(body, "")
	title_input.visible = mode in ["new", "save"]
	description_input.visible = mode in ["new", "save"]
	title_label.visible = title_input.visible
	description_label.visible = description_input.visible
	add_child(dialog)
	dialog.confirmed.connect(func():
		var key := StringName(key_input.text.strip_edges())
		var reason := Catalog.validate_key(str(key))
		if not reason.is_empty():
			error.text = reason
			return
		if mode in ["rename", "repair"]:
			reason = rename_entry(entry_index, key)
		elif mode == "copy":
			reason = create_style(key, source_entry.style)
		else:
			if title_input.text.strip_edges().is_empty():
				error.text = "请填写显示名称。"
				return
			var next := KeyEntry.new()
			next.id = key
			next.display_name = title_input.text.strip_edges()
			next.description = description_input.text
			if mode == "new":
				if key in Catalog.BASIC_KEYS or store.catalog.find(key) != null or state.pending.has(key):
					error.text = "键名已登记，请从选择器选择。"
					return
				var copied: InventoryItemVisualStyle = selected_entry().style if copy_style.button_pressed and selected_entry() != null else null
				reason = create_style(key, copied)
				if reason.is_empty():
					state.pending[key] = next
			else:
				state.pending[key] = next
				reason = store.save_entry(next)
				if reason.is_empty():
					state.pending.erase(key)
					message.text = "已保存到键库：" + store.path
		if not reason.is_empty():
			error.text = reason
			return
		_refresh_picker()
		request_rebuild()
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _touch() -> void:
	if not can_edit():
		return
	_update_style_problem()
	form.session.touch_feature(form.index)
	_refresh_picker()

func _session_changed() -> void:
	_refresh_picker()
	_update_style_problem()
	if is_instance_valid(preview):
		var entry := selected_entry()
		preview.set_style(entry.style if entry != null else null, form.resource if host_mode else null)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and store != null:
		store.refresh_if_changed()

func _exit_tree() -> void:
	if store != null and store.changed.is_connected(_refresh_picker):
		store.changed.disconnect(_refresh_picker)
	if is_instance_valid(form) and form.session.changed.is_connected(_session_changed):
		form.session.changed.disconnect(_session_changed)

func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = not can_edit()
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func switch_style_type(index: int) -> void:
	var entry := selected_entry()
	if not can_edit() or entry == null or entry.style == null or index < 0 or index >= Types.TYPES.size():
		return
	var target_script: Script = Types.TYPES[index].script
	if entry.style.get_script() == target_script:
		return
	var token := entry.get_instance_id()
	var drafts: Dictionary = state.types.get(token, {})
	if not drafts.has(entry.style.get_script()):
		drafts[entry.style.get_script()] = form.copy_resource(entry.style)
	var next: InventoryItemVisualStyle = drafts.get(target_script)
	if next == null:
		next = target_script.new()
		drafts[target_script] = next
	for field in ["use_border", "border_color", "use_fill", "fill_color"]:
		next.set(field, entry.style.get(field))
	entry.style = next
	state.types[token] = drafts
	_touch()
	request_rebuild()

func _update_style_problem() -> void:
	if not is_instance_valid(style_problem):
		return
	var entry := selected_entry()
	var reason := entry.style.validate_configuration() if entry != null and entry.style != null else &""
	style_problem.text = (str(state.key) + "：" + Types.describe_error(reason)) if not reason.is_empty() else ""
