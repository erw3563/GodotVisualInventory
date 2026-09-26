@tool
extends Button
## 搜索并选择外观键；弹层维护独立滚动区域。
signal key_selected(key: StringName)
signal opening
signal search_changed(value: String)
const Catalog = preload("res://addons/visual_inventory/gdbase/inventory/parts/cell_appearance/editor/inventory_appearance_key_catalog.gd")
var candidates: Array[Dictionary] = []
var selected_key: StringName
var search_text := ""
var dialog: AcceptDialog
var search: LineEdit
var results: ItemList

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip_text = true
	pressed.connect(open_picker)

func set_candidates(values: Array[Dictionary], key: StringName) -> void:
	candidates = values
	selected_key = key
	text = str(key)
	for item in candidates:
		if item.id == key:
			text = item.title + " · " + str(key) + "   ▼"
			tooltip_text = item.description
			break
	if is_instance_valid(results):
		_filter()

func open_picker() -> void:
	opening.emit()
	if not is_instance_valid(dialog):
		dialog = AcceptDialog.new()
		dialog.title = "选择外观键"
		dialog.ok_button_text = "关闭"
		dialog.unresizable = false
		var body := VBoxContainer.new()
		dialog.add_child(body)
		search = LineEdit.new()
		search.placeholder_text = "搜索名称、外观键、用途…"
		search.text = search_text
		body.add_child(search)
		results = ItemList.new()
		results.custom_minimum_size = Vector2(360, 280) * (EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0)
		results.size_flags_vertical = Control.SIZE_EXPAND_FILL
		results.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body.add_child(results)
		search.text_changed.connect(func(value: String):
			search_text = value
			search_changed.emit(value)
			_filter()
		)
		results.item_selected.connect(func(index: int):
			var key: Variant = results.get_item_metadata(index)
			if key is StringName:
				selected_key = key
				key_selected.emit(key)
				dialog.hide()
		)
		add_child(dialog)
	_filter()
	dialog.popup_centered()
	search.grab_focus()

func _filter() -> void:
	results.clear()
	for basic in [true, false]:
		var heading := false
		for item in candidates:
			if (item.id in Catalog.BASIC_KEYS) != basic:
				continue
			if not search_text.is_empty() and not (item.title + " " + str(item.id) + " " + item.description).to_lower().contains(search_text.to_lower()):
				continue
			if not heading:
				var group_index := results.add_item("基础键" if basic else "特殊键")
				results.set_item_disabled(group_index, true)
				heading = true
			var row := results.add_item(item.title + " · " + str(item.id) + "  [" + item.status + "]", item.get("icon"))
			results.set_item_metadata(row, item.id)
			results.set_item_tooltip(row, item.description)
			if item.id == selected_key:
				results.select(row)
	if results.item_count == 0:
		var empty := results.add_item("没有匹配的外观键")
		results.set_item_disabled(empty, true)
