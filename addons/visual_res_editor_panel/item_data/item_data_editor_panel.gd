@tool
extends VBoxContainer
const Form = preload("res://addons/visual_res_editor_panel/item_data/item_part_editor_form.gd")
const Catalog = preload("res://addons/visual_res_editor_panel/item_data/item_part_editor_catalog.gd")
const Chrome = preload("res://addons/visual_res_editor_panel/visual_res_editor_popup.gd")
enum PartAction { MOVE_UP, MOVE_DOWN, REMOVE }
signal close_requested
signal new_requested
var session: RefCounted
var catalog := Catalog.new()
var part_list: Tree
var feature_toolbar: VBoxContainer
var detail_scroll: ScrollContainer
var detail: VBoxContainer
var form: Control
var status: Label
var selected := 0
var _pending_rebuild := false
var _shutdown := false
var _refreshing_list := false
var _ignore_selection := false

func setup(value: RefCounted) -> void:
	session = value
	catalog.refresh()
	session.structure_changed.connect(_queue_rebuild)
	session.changed.connect(_update_status)

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_instance_valid(part_list):
		_refresh_list()

func _ready() -> void:
	var toolbar := HBoxContainer.new()
	add_child(toolbar)
	_button(toolbar, "新建物品", func(): new_requested.emit())
	_button(toolbar, "应用", _apply)
	_button(toolbar, "保存", _save)
	_button(toolbar, "另存为", _save_as)
	_button(toolbar, "重新载入", _reload)
	_button(toolbar, "关闭", request_close)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 240
	left.add_theme_constant_override("separation", 8)
	split.add_child(left)
	_button(left, "＋ 添加功能", _add_dialog)
	part_list = Tree.new()
	part_list.hide_root = true
	part_list.columns = 1
	part_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Chrome.flatten_list_surface(part_list)
	part_list.item_selected.connect(_on_part_selected)
	part_list.button_clicked.connect(_on_part_action)
	left.add_child(part_list)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	split.add_child(margin)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	margin.add_child(right)
	feature_toolbar = VBoxContainer.new()
	feature_toolbar.name = "FeatureToolbar"
	right.add_child(feature_toolbar)
	detail_scroll = ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(detail_scroll)
	detail = VBoxContainer.new()
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.add_theme_constant_override("separation", 10)
	detail_scroll.add_child(detail)
	_rebuild()

func _queue_rebuild() -> void:
	if _pending_rebuild or _shutdown:
		return
	_pending_rebuild = true
	_rebuild.call_deferred()

func _rebuild() -> void:
	_pending_rebuild = false
	_ignore_selection = false
	if _shutdown or not is_instance_valid(part_list):
		return
	for child in feature_toolbar.get_children():
		feature_toolbar.remove_child(child)
		child.queue_free()
	for child in detail.get_children():
		detail.remove_child(child)
		child.queue_free()
	form = null
	if selected < 0 or selected >= session.entries.size():
		selected = 0
	_refresh_list()
	_build_form()
	_update_status()

func _refresh_list() -> void:
	_refreshing_list = true
	part_list.clear()
	var root := part_list.create_item()
	var up_icon := get_theme_icon(&"MoveUp", &"EditorIcons")
	var down_icon := get_theme_icon(&"MoveDown", &"EditorIcons")
	var remove_icon := get_theme_icon(&"Remove", &"EditorIcons")
	_row(root, "基础信息", 0)
	var part_count: int = session.draft.parts.size()
	for i in part_count:
		var part: ItemPart = session.draft.parts[i]
		var data: Dictionary = catalog.find(part.get_script()) if part != null else {}
		var title := str(data.get("title", str(part.get_script().get_global_name()) if part != null else "空功能"))
		var row := _row(root, title, i + 1)
		row.add_button(0, up_icon, PartAction.MOVE_UP, i == 0, "上移")
		row.add_button(0, down_icon, PartAction.MOVE_DOWN, i == part_count - 1, "下移")
		row.add_button(0, remove_icon, PartAction.REMOVE, false, "删除")
	_refreshing_list = false

func _row(root: TreeItem, title: String, index: int) -> TreeItem:
	var row := part_list.create_item(root)
	row.set_text(0, title)
	row.set_metadata(0, index)
	if selected == index:
		row.select(0)
	return row

func _on_part_selected() -> void:
	if _refreshing_list or _ignore_selection:
		return
	var row := part_list.get_selected()
	var index := int(row.get_metadata(0)) if row != null else 0
	if selected == index:
		return
	selected = index
	_queue_rebuild()

func _on_part_action(row: TreeItem, column: int, id: int, _mouse_button_index: int) -> void:
	if column != 0:
		return
	_ignore_selection = true
	var index := int(row.get_metadata(0))
	match id:
		PartAction.MOVE_UP:
			session.move_part(index, -1)
			selected = maxi(1, index - 1)
		PartAction.MOVE_DOWN:
			session.move_part(index, 1)
			selected = mini(session.entries.size() - 1, index + 1)
		PartAction.REMOVE:
			session.remove_part(index)
			selected = mini(index, session.entries.size() - 1)

func _build_form() -> void:
	var entry: Dictionary = session.entries[selected]
	var part: Resource = entry.draft
	if selected == 0:
		_label(feature_toolbar, "基础信息")
		_label(feature_toolbar, "编辑中 · 独有配置")
		_build_fields({})
		return
	if part == null:
		_label(feature_toolbar, "空功能")
		_label(detail, "空功能无法配置，请从列表删除。")
		return
	var data: Dictionary = catalog.find(part.get_script())
	var title := str(data.get("title", str(part.get_script().get_global_name())))
	_label(feature_toolbar, title)
	var source: Resource = entry.reference
	var editing := "编辑中" if session.feature_editable(selected) else "只读"
	var ownership := "独有配置" if source == null else "当前引用"
	_label(feature_toolbar, editing + " · " + ownership)
	feature_toolbar.tooltip_text = source.resource_path if source != null else "新建／独有草稿"
	var actions := HFlowContainer.new()
	feature_toolbar.add_child(actions)
	var edit := _button(actions, "编辑共享引用", func(): session.edit_shared(selected))
	edit.name = "EditReference"
	edit.disabled = source == null or entry.editable or data.is_empty()
	var unique := _button(actions, "复制为独有配置", func(): session.make_unique(selected))
	unique.name = "MakeUnique"
	unique.disabled = data.is_empty()
	_label(detail, str(data.get("description", part.get_script().resource_path)))
	if data.is_empty():
		_label(detail, "此自定义功能缺少编辑支持，原引用和全部字段保留；可排序或删除。")
		return
	_build_fields(data)

func _build_fields(data: Dictionary) -> void:
	form = Form.new()
	form.setup(session, selected)
	form.rebuild_requested.connect(_queue_rebuild)
	form.set_field_choices("tags", catalog.tag_names)
	detail.add_child(form)
	if selected == 0:
		for key in {"item_name": "物品名称", "icon": "图标", "max_num": "最大堆叠数", "item_description": "物品描述"}:
			form.add_field(key, {"item_name": "物品名称", "icon": "图标", "max_num": "最大堆叠数", "item_description": "物品描述"}[key])
	else:
		data.adapter.build(form)

func _add_dialog() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "添加物品功能"
	dialog.dialog_hide_on_ok = false
	dialog.ok_button_text = "添加"
	dialog.cancel_button_text = "完成"
	var options := ItemList.new()
	options.custom_minimum_size = Vector2(380, 360)
	options.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var types: Array[Script] = []
	var refresh_options := func():
		var indices := options.get_selected_items()
		var previous := indices[0] if not indices.is_empty() else 0
		options.clear()
		types.clear()
		for entry in catalog.entries:
			var part: ItemPart = entry.type.new()
			if not part.allows_multiple() and session.draft.has_type_part(entry.type.get_part_type()):
				continue
			options.add_item(entry.title)
			types.append(entry.type)
		dialog.get_ok_button().disabled = types.is_empty()
		if not types.is_empty():
			options.select(mini(previous, types.size() - 1))
	dialog.add_child(options)
	refresh_options.call()
	var add_selected := func():
		var indices := options.get_selected_items()
		if not indices.is_empty() and session.add_part(types[indices[0]]):
			selected = session.entries.size() - 1
			refresh_options.call()
	dialog.confirmed.connect(add_selected)
	options.item_activated.connect(func(_index: int): add_selected.call())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered(Vector2i(420, 460))

func _apply() -> void:
	var reason: String = session.apply()
	status.text = reason if not reason.is_empty() else "已应用"

func _save() -> void:
	if session.target.resource_path.is_empty() or session.target.resource_path.contains("::"):
		_save_as()
		return
	var reason: String = session.apply()
	if reason.is_empty():
		var error := ResourceSaver.save(session.target)
		reason = "已保存" if error == OK else error_string(error)
	status.text = reason

func _save_as() -> void:
	var dialog := EditorFileDialog.new()
	dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	dialog.access = EditorFileDialog.ACCESS_RESOURCES
	dialog.add_filter("*.tres", "物品资源")
	dialog.current_file = "new_item.tres"
	dialog.file_selected.connect(func(path: String):
		var reason: String = session.save_as(path)
		status.text = "已另存为 " + path if reason.is_empty() else reason
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.65)

func _reload() -> void:
	_confirm_discard(func(): session.reload())

func request_close() -> void:
	_confirm_discard(func(): close_requested.emit())

func _confirm_discard(action: Callable) -> void:
	if not session.is_dirty():
		action.call()
		return
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "放弃未应用的物品修改？"
	dialog.confirmed.connect(func(): dialog.queue_free(); action.call())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func _update_status() -> void:
	if is_instance_valid(status):
		status.text = ("有未应用修改" if session.is_dirty() else "已同步") + " · " + session.validate()

func shutdown() -> void:
	_shutdown = true
	if session != null:
		if session.structure_changed.is_connected(_queue_rebuild):
			session.structure_changed.disconnect(_queue_rebuild)
		if session.changed.is_connected(_update_status):
			session.changed.disconnect(_update_status)

func _label(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button
