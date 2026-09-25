class_name CustomItemDescriptionPanel
extends ItemDescriptionPanelBase
## 自定义物品说明面板，显示 ItemInstanceData 基础信息及其 instance_states 的描述控件。
## 当实例状态较多时，会有显示不全的问题。

## 盒子容器控件，各状态的说明控件会添加为该控件的子节点
@export var box_container: Control
@export_enum("黑名单","白名单") var show_mode:int = 0
## 需要忽略的状态类型。在黑名单模式下启动。
@export var ignore_list:Array[String]
## 需要显示的状态类型。在白名单模式下启动。
@export var pass_list:Array[String]
## 是否在描述控件之间添加线段节点分隔
@export var is_line_division:bool = true
## 内容盒父节点为 ScrollContainer 时的最大高度；0 表示不限高。
@export var max_box_height: float = 0.0
var boxes:Array[Control]
var _description_generation := 0

## 更新方法，在子类中个体实现
func _try_update_description(content_only: bool = false):
	_description_generation += 1
	var generation := _description_generation
	var scroll := box_container.get_parent() as ScrollContainer
	var scroll_position := Vector2i(scroll.scroll_horizontal, scroll.scroll_vertical) if scroll != null else Vector2i.ZERO
	clear_all_description()
	if !item_instance_data:
		await _fit_scroll_box_height()
		return
	if _check_section_type_to_show(ItemDescriptionSectionBuilder.BASE_SECTION_TYPE):
		var base_info_controls := _create_base_info_controls(item_instance_data)
		for base_control in base_info_controls:
			box_container.add_child(base_control)
			boxes.append(base_control)
			if is_line_division:
				var base_hseparator := HSeparator.new()
				box_container.add_child(base_hseparator)
				boxes.append(base_hseparator)
	for description_section in ItemDescriptionSectionBuilder.build(item_instance_data):
		var section_type: String = description_section.get("section_type", "")
		if !_check_section_type_to_show(section_type):
			continue
		var controls: Array = description_section.get("controls", [])
		if controls.is_empty():
			continue
		for control in controls:
			box_container.add_child(control)
			boxes.append(control)
			if is_line_division:
				var hseparator := HSeparator.new()
				box_container.add_child(hseparator)
				boxes.append(hseparator)
	await _fit_scroll_box_height()
	if generation == _description_generation and item_instance_data != null:
		if content_only and is_instance_valid(scroll):
			scroll.scroll_horizontal = scroll_position.x
			scroll.scroll_vertical = scroll_position.y
		_finish_description_update(content_only)

## 按内容增高滚动容器，超过 max_box_height 后出现滚动条。
func _fit_scroll_box_height() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or max_box_height <= 0.0 or not is_instance_valid(box_container):
		return
	var scroll := box_container.get_parent() as ScrollContainer
	if scroll == null:
		return
	await get_tree().process_frame
	if not is_inside_tree() or is_queued_for_deletion() or not is_instance_valid(scroll) or not is_instance_valid(box_container):
		return
	var content_height := box_container.get_combined_minimum_size().y
	scroll.custom_minimum_size.y = minf(content_height, max_box_height)

## 清除旧数据
func clear_all_description():
	for box in boxes:
		if is_instance_valid(box):
			box.queue_free()
	boxes.clear()

## 根据 show_mode 规则判断指定类型是否显示。
func _check_section_type_to_show(section_type: String) -> bool:
	var is_visible := true
	match show_mode:
		0:
			if ignore_list.has(section_type):
				is_visible = false
		1:
			if !pass_list.has(section_type):
				is_visible = false
	return is_visible

## 基于 ItemInstanceData 字段创建基础信息描述控件。
func _create_base_info_controls(item_instance: ItemInstanceData) -> Array[Control]:
	var result_controls: Array[Control]

	var title_label := Label.new()
	title_label.text = "基础信息"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_controls.append(title_label)

	var item_name_label := Label.new()
	item_name_label.text = "名字：" + item_instance.get_item_name()
	result_controls.append(item_name_label)

	var item_icon_texture := TextureRect.new()
	item_icon_texture.texture = item_instance.get_item_icon()
	item_icon_texture.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	result_controls.append(item_icon_texture)

	var item_description_label := Label.new()
	item_description_label.text = "描述：" + item_instance.get_item_description()
	item_description_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	result_controls.append(item_description_label)

	var num_label := Label.new()
	num_label.text = "数量：%d / %d" % [item_instance.get_item_num(), item_instance.get_item_max_num()]
	result_controls.append(num_label)

	return result_controls
