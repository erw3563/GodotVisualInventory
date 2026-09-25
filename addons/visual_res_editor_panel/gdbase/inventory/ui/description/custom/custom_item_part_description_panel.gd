class_name CustomItemPartDescriptionPanel
extends CustomItemDescriptionPanel
## 将基础信息与各实例状态分页显示，一次只显示一个段落。

signal item_part_changed

## 类型切换按钮
@export var type_button_container:Control
## section_type, Array[Control]
var item_part_panels:Dictionary
var current_item_part
var buttons:Array[Button]

## 更新方法，在子类中个体实现
func _try_update_description(content_only: bool = false):
	_description_generation += 1
	var generation := _description_generation
	var selected_section = current_item_part if content_only else null
	var scroll := box_container.get_parent() as ScrollContainer
	var scroll_position := Vector2i(scroll.scroll_horizontal, scroll.scroll_vertical) if scroll != null else Vector2i.ZERO
	clear_all_description()
	if !item_instance_data:
		return
	if _check_section_type_to_show(ItemDescriptionSectionBuilder.BASE_SECTION_TYPE):
		var base_controls := _create_base_info_controls(item_instance_data)
		if !base_controls.is_empty():
			var base_part_type := ItemDescriptionSectionBuilder.BASE_SECTION_TYPE
			if !current_item_part:
				current_item_part = base_part_type
			var base_type_controls: Array[Control]
			for base_control in base_controls:
				base_control.hide()
				box_container.add_child(base_control)
				boxes.append(base_control)
				base_type_controls.append(base_control)
				if is_line_division:
					var base_hseparator := HSeparator.new()
					base_hseparator.hide()
					box_container.add_child(base_hseparator)
					boxes.append(base_hseparator)
					base_type_controls.append(base_hseparator)
			item_part_panels[base_part_type] = base_type_controls
			var base_button := Button.new()
			base_button.text = base_part_type
			base_button.button_up.connect(show_item_part.bind(base_part_type))
			type_button_container.add_child(base_button)
			buttons.append(base_button)
	for description_section in ItemDescriptionSectionBuilder.build(item_instance_data):
		var section_type: String = description_section.get("section_type", "")
		if !_check_section_type_to_show(section_type):
			continue
		var controls: Array = description_section.get("controls", [])
		if controls.is_empty():
			continue
		if !current_item_part:
			current_item_part = section_type
		var type_controls:Array[Control]
		for control in controls:
			control.hide()
			box_container.add_child(control)
			boxes.append(control)
			type_controls.append(control)
			if is_line_division:
				var hseparator := HSeparator.new()
				hseparator.hide()
				box_container.add_child(hseparator)
				boxes.append(hseparator)
				type_controls.append(hseparator)
		item_part_panels[section_type] = type_controls
		var button := Button.new()
		button.text = section_type
		button.button_up.connect(show_item_part.bind(section_type))
		type_button_container.add_child(button)
		buttons.append(button)
	if selected_section != null and item_part_panels.has(selected_section):
		current_item_part = selected_section
	if current_item_part and item_part_panels.has(current_item_part):
		await show_item_part(current_item_part, not content_only)
	await _fit_scroll_box_height()
	if generation == _description_generation and item_instance_data != null:
		if content_only and is_instance_valid(scroll):
			scroll.scroll_horizontal = scroll_position.x
			scroll.scroll_vertical = scroll_position.y
		_finish_description_update(content_only)

func show_item_part(item_part_key, notify: bool = true):
	var generation := _description_generation
	if current_item_part != null and item_part_panels.has(current_item_part):
		for control in item_part_panels[current_item_part]:
			control.hide()
	current_item_part = item_part_key
	if !item_part_panels.has(item_part_key):
		return
	for control in item_part_panels[item_part_key]:
		control.show()
	await get_tree().process_frame
	if not is_inside_tree() or generation != _description_generation:
		return
	await get_tree().process_frame
	if notify and is_inside_tree() and generation == _description_generation:
		item_part_changed.emit()

## 清除旧数据
func clear_all_description():
	super.clear_all_description()
	for button in buttons:
		button.queue_free()
	buttons.clear()
	item_part_panels.clear()
	current_item_part = null
