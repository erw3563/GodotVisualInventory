@tool
extends HSplitContainer
const Form = preload("res://addons/visual_res_editor_panel/inventory_host_definition/inventory_host_feature_form.gd")
const Chrome = preload("res://addons/visual_res_editor_panel/visual_res_editor_popup.gd")
enum FeatureAction { MOVE_UP, MOVE_DOWN, REMOVE }
var session: RefCounted
var feature_list: Tree
var details: VBoxContainer
var toolbar: VBoxContainer
var detail_scroll: ScrollContainer
var _active_view: Dictionary = {}
var _restoring_scroll := false
var _view_generation := 0
var form: Control
var add_dialog: AcceptDialog
var add_results: VBoxContainer
var search_box: LineEdit
var category: OptionButton
var addition_status: Label
var _add_buttons: Dictionary = {}
var _add_previews: Dictionary = {}
var _preview_labels: Dictionary = {}
var _queued := false
var _built := false
var _refreshing_list := false

func setup(value: RefCounted) -> void:
	session = value
	session.structure_changed.connect(request_rebuild)
	session.changed.connect(_refresh_list)
	session.changed.connect(_refresh_add_buttons)

func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _built:
		_refresh_list()

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_offset = 260
	var left := VBoxContainer.new()
	left.name = "FeatureSidebar"
	left.custom_minimum_size.x = 200
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 8)
	add_child(left)
	var heading := Label.new()
	heading.name = "Heading"
	heading.text = "已添加功能"
	left.add_child(heading)
	var add_button := _button(left, "＋ 添加功能", open_add)
	add_button.name = "AddFeature"
	add_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	feature_list = Tree.new()
	feature_list.name = "FeatureList"
	feature_list.hide_root = true
	feature_list.columns = 1
	feature_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Chrome.flatten_list_surface(feature_list)
	feature_list.item_selected.connect(_on_feature_selected)
	feature_list.button_clicked.connect(_on_feature_action)
	left.add_child(feature_list)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	add_child(margin)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	margin.add_child(right)
	toolbar = VBoxContainer.new()
	toolbar.name = "FeatureToolbar"
	right.add_child(toolbar)
	detail_scroll = ScrollContainer.new()
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(detail_scroll)
	detail_scroll.get_v_scroll_bar().value_changed.connect(func(value: float):
		if not _restoring_scroll:
			_active_view["scroll"] = int(value)
	)
	details = VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 10)
	detail_scroll.add_child(details)
	_built = true
	_rebuild()

func request_rebuild() -> void:
	if _queued or not is_inside_tree():
		return
	_queued = true
	_rebuild.call_deferred()

func _rebuild() -> void:
	_queued = false
	if not _built or not is_inside_tree():
		return
	_restoring_scroll = true
	_view_generation += 1
	for child in toolbar.get_children():
		toolbar.remove_child(child)
		child.queue_free()
	for child in details.get_children():
		details.remove_child(child)
		child.queue_free()
	form = null
	_refresh_list()
	var index: int = session.selected
	_active_view = session.feature_view(index) if index >= 0 and index < session.entries.size() else {}
	_restore_scroll(_view_generation)
	if index < 0 or index >= session.entries.size():
		_label(details, "尚未选择功能。点击「＋ 添加功能」，选择希望背包具备的能力。")
		return
	var entry: Dictionary = session.entries[index]
	_label(toolbar, session.feature_catalog.title(entry.draft))
	if entry.draft == null:
		_label(details, "空功能无法配置，请从列表删除。")
		return
	var info: Dictionary = session.feature_catalog.find(entry.draft.get_script())
	_label(details, info.get("description", entry.draft.get_script().resource_path))
	var source: Resource = entry.reference
	var editing := "编辑中" if session.feature_editable(index) else "只读"
	var ownership := "独有配置" if source == null or _active_view.get("unique", false) else "当前引用"
	_label(toolbar, editing + " · " + ownership)
	toolbar.tooltip_text = source.resource_path if source != null else "新建／独有草稿"
	var actions := HFlowContainer.new()
	toolbar.add_child(actions)
	var edit := _button(actions, "编辑共享引用", func(): session.edit_feature_reference(index))
	edit.name = "EditReference"
	edit.disabled = source == null or entry.editable or info.is_empty()
	var unique := _button(actions, "复制为独有配置", func(): session.unique_feature(index))
	unique.name = "MakeUnique"
	unique.disabled = info.is_empty()
	form = Form.new()
	form.setup(session, index)
	details.add_child(form)
	if not info.is_empty():
		info.adapter.build(form)
		form.rebuild_requested.connect(request_rebuild)
	else:
		_label(details, "此自定义功能缺少编辑支持，原引用和全部字段保留；可排序或删除。")

func _restore_scroll(generation: int) -> void:
	for frame in 3:
		await get_tree().process_frame
		if not is_inside_tree() or generation != _view_generation:
			return
	detail_scroll.scroll_vertical = int(_active_view.get("scroll", 0))
	_restoring_scroll = false

func _refresh_list() -> void:
	if not _built:
		return
	var problems: Dictionary = {}
	for item in session.diagnostics():
		if item.has("error"):
			problems[item.index] = item.error
	_refreshing_list = true
	feature_list.clear()
	var root := feature_list.create_item()
	var up_icon := get_theme_icon(&"MoveUp", &"EditorIcons")
	var down_icon := get_theme_icon(&"MoveDown", &"EditorIcons")
	var remove_icon := get_theme_icon(&"Remove", &"EditorIcons")
	for i in session.entries.size():
		var feature: Resource = session.entries[i].draft
		var row := feature_list.create_item(root)
		row.set_metadata(0, i)
		row.set_text(0, ("⚠ " if problems.has(i) else "") + session.feature_catalog.title(feature))
		row.set_tooltip_text(0, problems.get(i, ""))
		row.add_button(0, up_icon, FeatureAction.MOVE_UP, i == 0, "上移")
		row.add_button(0, down_icon, FeatureAction.MOVE_DOWN, i == session.entries.size() - 1, "下移")
		row.add_button(0, remove_icon, FeatureAction.REMOVE, false, "删除")
		if i == session.selected:
			row.select(0)
	_refreshing_list = false
	_refresh_add_buttons()

func _on_feature_selected() -> void:
	if _refreshing_list:
		return
	var row := feature_list.get_selected()
	session.select_feature(int(row.get_metadata(0)) if row != null else -1)

func _on_feature_action(row: TreeItem, column: int, id: int, _mouse_button_index: int) -> void:
	if column != 0:
		return
	var index := int(row.get_metadata(0))
	match id:
		FeatureAction.MOVE_UP:
			session.move_feature(index, -1)
		FeatureAction.MOVE_DOWN:
			session.move_feature(index, 1)
		FeatureAction.REMOVE:
			session.remove_feature(index)

func open_add() -> void:
	session.feature_catalog.refresh()
	if is_instance_valid(add_dialog):
		add_dialog.queue_free()
	add_dialog = AcceptDialog.new()
	add_dialog.title = "添加功能"
	add_dialog.unresizable = false
	add_dialog.ok_button_text = "关闭"
	var body := VBoxContainer.new()
	add_dialog.add_child(body)
	search_box = LineEdit.new()
	search_box.placeholder_text = "搜索能力名称、用途…"
	body.add_child(search_box)
	category = OptionButton.new()
	category.add_item("全部分类")
	var categories: Array[String] = []
	for entry in session.feature_catalog.entries:
		if entry.category not in categories:
			categories.append(entry.category)
	for title in categories:
		category.add_item(title)
	body.add_child(category)
	addition_status = Label.new()
	addition_status.name = "AdditionStatus"
	addition_status.custom_minimum_size.x = 580
	addition_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	addition_status.text = "选择功能时补齐依赖；相同身份提供替换并添加。"
	body.add_child(addition_status)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(580, 370)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	add_results = VBoxContainer.new()
	add_results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(add_results)
	search_box.text_changed.connect(func(_text: String): _refresh_add())
	category.item_selected.connect(func(_index: int): _refresh_add())
	add_child(add_dialog)
	_refresh_add()
	add_dialog.popup_centered_clamped(Vector2i(620, 500))
	search_box.grab_focus()

func _refresh_add() -> void:
	_add_buttons.clear()
	_add_previews.clear()
	_preview_labels.clear()
	for child in add_results.get_children():
		add_results.remove_child(child)
		child.queue_free()
	for problem in session.feature_catalog.errors:
		_label(add_results, problem)
	var group: String = "" if category.selected == 0 else category.get_item_text(category.selected)
	var results: Array = session.feature_catalog.search(search_box.text, group)
	var last_category := ""
	for entry in results:
		var entry_category := str(entry.get("category", ""))
		if entry == results.front() or entry_category != last_category:
			var heading := HBoxContainer.new()
			heading.name = "CategoryHeading"
			heading.add_theme_constant_override("separation", 8)
			add_results.add_child(heading)
			var title := Label.new()
			title.text = entry_category
			title.autowrap_mode = TextServer.AUTOWRAP_OFF
			heading.add_child(title)
			var separator := HSeparator.new()
			separator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			separator.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			heading.add_child(separator)
			last_category = entry_category
		var existing := false
		for feature in session.feature_drafts():
			if feature != null and feature.get_script() == entry.type:
				existing = true
		var item := VBoxContainer.new()
		add_results.add_child(item)
		var row := HBoxContainer.new()
		row.name = "Header"
		item.add_child(row)
		var button := _button(row, entry.title + (" · 已添加" if existing else ""), func(): _add_feature(entry.type))
		_add_buttons[entry.type] = button
		button.disabled = existing or not session.feature_catalog.errors.is_empty()
		button.name = "Add"
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.tooltip_text = entry.description
		var description := VBoxContainer.new()
		description.name = "Description"
		description.visible = false
		item.add_child(description)
		var preview_label := Label.new()
		preview_label.name = "AdditionPreview"
		preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		preview_label.visible = false
		description.add_child(preview_label)
		_preview_labels[entry.type] = preview_label
		_label(description, entry.description)
		if not str(entry.get("keywords", "")).is_empty():
			_label(description, entry.keywords)
		var toggle := Button.new()
		toggle.name = "ToggleDescription"
		toggle.text = "展开描述"
		toggle.toggle_mode = true
		toggle.toggled.connect(func(expanded: bool):
			description.visible = expanded
			toggle.text = "收起描述" if expanded else "展开描述"
		)
		row.add_child(toggle)
	if results.is_empty():
		_label(add_results, "没有匹配的功能。")

	_refresh_add_buttons()

func _refresh_add_buttons() -> void:
	for type in _add_buttons:
		var button: Button = _add_buttons[type]
		if not is_instance_valid(button):
			continue
		var preview: Dictionary = session.preview_feature_addition(type)
		_add_previews[type] = preview
		var status := "添加"
		if preview.error_code == &"feature_duplicate":
			status = "已添加"
		elif preview.ok and not preview.removed_types.is_empty():
			status = "替换并添加"
		button.text = session.feature_catalog.type_title(type) + " · " + status
		button.disabled = not preview.ok
		var lines: Array[String] = []
		if preview.ok:
			if not preview.removed_types.is_empty():
				lines.append("将替换：" + _type_names(preview.removed_types, "、"))
				for index in preview.removed_types.size():
					lines.append("%s占用身份：%s" % [session.feature_catalog.type_title(preview.removed_types[index]), "、".join(preview.removed_roles[index].map(session.feature_catalog.role_title))])
			if not preview.dependency_types.is_empty():
				lines.append("自动添加：" + _type_names(preview.dependency_types, "、"))
		elif preview.error_code != &"feature_duplicate":
			lines.append(_addition_message(preview))
		var label: Label = _preview_labels.get(type)
		if is_instance_valid(label):
			label.text = "\n".join(lines)
			label.visible = not lines.is_empty()

func _add_feature(type: Script) -> void:
	var preview: Dictionary = _add_previews.get(type, {})
	if preview.is_empty():
		_refresh_add_buttons()
		return
	var result: Dictionary = session.commit_feature_addition(preview)
	addition_status.text = _addition_message(result)
	_refresh_add_buttons()
func _addition_message(result: Dictionary) -> String:
	var title: String = session.feature_catalog.type_title(result.requested_type)
	if result.ok:
		var message := "已添加：" + title
		if not result.removed_types.is_empty():
			message += "；已替换：" + _type_names(result.removed_types, "、")
		if not result.dependency_types.is_empty():
			message += "；自动添加：" + _type_names(result.dependency_types, "、")
		return message
	var chain := _type_names(result.dependency_chain, " → ")
	if result.error_code == &"feature_conflict":
		var messages: Array[String] = []
		for conflict in result.conflicts:
			messages.append("%s与%s冲突" % [session.feature_catalog.type_title(conflict.type), session.feature_catalog.type_title(conflict.other_type)])
		return "添加失败：%s。%s。请先调整已有功能。" % [chain, "；".join(messages)]
	var reason: String = {
		&"feature_addition_preview_stale": "配置已变化，请查看更新后的替换方案再添加",
		&"replacement_dependency_missing": "替换会移除其他功能所需依赖",
		&"configuration_invalid": "候选组合存在配置错误",
		&"catalog_invalid": "功能目录存在配置错误",
		&"feature_unavailable": "所选功能缺少有效编辑适配",
		&"feature_duplicate": "该功能已添加",
		&"dependency_unavailable": "所需功能缺少有效编辑适配",
		&"declaration_invalid": "功能添加声明无效",
		&"dependency_cycle": "功能依赖形成循环",
		&"dependency_order_conflict": "已有功能顺序与依赖顺序冲突，请调整列表顺序"
	}.get(result.error_code, "功能添加失败")
	return "添加失败：%s。%s%s" % [reason, chain, "。" + result.detail if not result.detail.is_empty() else ""]

func _type_names(types: Array, separator: String) -> String:
	var names: Array[String] = []
	for type in types:
		names.append(session.feature_catalog.type_title(type))
	return separator.join(names)

func _label(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func shutdown() -> void:
	if session != null:
		if session.structure_changed.is_connected(request_rebuild):
			session.structure_changed.disconnect(request_rebuild)
		if session.changed.is_connected(_refresh_list):
			session.changed.disconnect(_refresh_list)

func _exit_tree() -> void:
	shutdown()
