@tool
extends RefCounted
## 数值条目编辑只写入表单授权的草稿，不依赖编辑器插件类。
func describe() -> Dictionary:
	return {"type": ItemNumericPart, "title": "数值", "fields": {"entries": "数值条目", "instance_state_key": "实例状态键"}}

func build(form: Control) -> void:
	form.declared_fields.append("entries")
	form.controls["entries"] = form
	var editable: bool = form.session.feature_editable(form.index)
	var part: ItemNumericPart = form.resource
	form.add_note("固定数值保存在模板中；实例数值分别记录每件物品的当前值。修改条目键会按删除旧值、初始化新值处理。")
	var row := HBoxContainer.new()
	form.add_child(row)
	for preset in ["自定义数值", "饱食度", "耐久度", "新鲜度", "金币价值", "费用价值"]:
		var button := Button.new()
		button.text = "＋ " + preset
		button.disabled = not editable
		row.add_child(button)
		form.controls["add_" + preset] = button
		if editable:
			button.pressed.connect(func():
				var entry := make_preset(preset)
				var base := String(entry.key)
				var suffix := 2
				while part.find_entry(entry.key) != null:
					entry.key = StringName(base + "_" + str(suffix))
					suffix += 1
				part.entries.append(entry)
				form.session.touch_feature(form.index)
				form.rebuild_requested.emit()
			)
	for i in part.entries.size():
		var entry := part.entries[i]
		var box := VBoxContainer.new()
		form.add_child(box)
		var header := HBoxContainer.new()
		box.add_child(header)
		var title := Label.new()
		title.text = entry.title() if entry != null else "空条目"
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(title)
		for action in ["上移", "下移", "删除"]:
			var button := Button.new()
			button.text = action
			form.controls[str(i) + "." + action] = button
			header.add_child(button)
			button.disabled = not editable or action == "上移" and i == 0 or action == "下移" and i == part.entries.size() - 1
			if editable:
				button.pressed.connect(func():
					if action == "删除":
						part.entries.remove_at(i)
					else:
						var next := i + (-1 if action == "上移" else 1)
						part.entries.remove_at(i)
						part.entries.insert(next, entry)
					form.session.touch_feature(form.index)
					form.rebuild_requested.emit()
				)
		if entry == null:
			continue
		for pair in [["display_name", "名称"], ["key", "稳定键"], ["number_type", "数值类型"], ["storage_mode", "存储模式"]]:
			_field(form, box, entry, pair[0], pair[1], i, editable)
		if entry.storage_mode == ItemNumericEntry.StorageMode.FIXED:
			_field(form, box, entry, "value", "模板数值", i, editable)
		else:
			_field(form, box, entry, "initialize_at_maximum", "初始填满有效上限", i, editable)
			if not entry.initialize_at_maximum:
				_field(form, box, entry, "initial_value", "初始值", i, editable)
		_field(form, box, entry, "minimum_enabled", "启用下限", i, editable)
		if entry.minimum_enabled:
			_field(form, box, entry, "minimum", "下限", i, editable)
		_field(form, box, entry, "maximum_enabled", "启用上限", i, editable)
		if entry.maximum_enabled:
			_field(form, box, entry, "maximum", "上限", i, editable)
		var toggle := Button.new()
		toggle.text = "高级设置"
		toggle.toggle_mode = true
		box.add_child(toggle)
		var advanced := VBoxContainer.new()
		box.add_child(advanced)
		advanced.hide()
		toggle.toggled.connect(func(open: bool): advanced.visible = open)
		if entry.storage_mode == ItemNumericEntry.StorageMode.INSTANCE:
			_field(form, advanced, entry, "merge_mode", "合并方式", i, editable)
			if entry.maximum_enabled:
				_field(form, advanced, entry, "maximum_floor", "修饰后上限的最低值", i, editable)
		_field(form, advanced, entry, "display_format", "显示格式", i, editable)
	form.add_field("instance_state_key", "高级：实例状态键（留空使用 Numeric）")

func _field(form: Control, parent: Node, entry: ItemNumericEntry, key: String, label: String, index: int, editable: bool) -> void:
	form._label(parent, label)
	var info: Dictionary = form._property(entry, key).duplicate()
	var names := {"number_type": "整数,浮点", "storage_mode": "固定模板值,实例当前值", "merge_mode": "禁止合并,相等才合并,按数量加权", "display_format": "普通数字,百分比"}
	if names.has(key):
		info.hint_string = names[key]
	var control: Control = form._render(entry.get(key), info, func(value: Variant):
		if not editable:
			return
		entry.set(key, value)
		form.session.touch_feature(form.index)
		if key in ["storage_mode", "number_type", "minimum_enabled", "maximum_enabled", "initialize_at_maximum"]:
			form.rebuild_requested.emit()
	, parent, 0, [form.resource, entry])
	if not editable:
		form._set_read_only(control)
	form.controls[str(index) + "." + key] = control

func make_preset(name: String) -> ItemNumericEntry:
	match name:
		"金币价值":
			return ItemNumericEntry.fixed(&"coin", 1, "金币价值")
		"费用价值":
			return ItemNumericEntry.fixed(&"cost", 1, "费用价值")
		"饱食度":
			return ItemNumericEntry.fixed(&"food", 20, "饱食度")
		"耐久度":
			var entry := ItemNumericEntry.bounded(&"durability", 100, 0, 100, ItemNumericEntry.MergeMode.REJECT, true)
			entry.display_name = "耐久"
			entry.maximum_floor = 1
			return entry
		"新鲜度":
			var entry := ItemNumericEntry.bounded(&"freshness", 1.0, 0.0, 1.0, ItemNumericEntry.MergeMode.WEIGHTED)
			entry.display_name = "新鲜度"
			entry.display_format = ItemNumericEntry.DisplayFormat.PERCENT
			return entry
	return ItemNumericEntry.fixed(&"value", 0, "数值")

func diagnose(part: ItemPart) -> String:
	return str(part.call("validate_configuration"))
