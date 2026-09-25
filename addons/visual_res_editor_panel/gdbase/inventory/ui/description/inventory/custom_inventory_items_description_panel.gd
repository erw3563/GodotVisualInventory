class_name CustomInventoryItemsDescriptionPanel
extends Node
## 背包整包说明面板，为每个物品实例列出基础信息与 instance_states 描述。

signal description_updated

@export var inventory_data:InventoryData
## 盒子容器控件，各物品的说明控件会添加为该控件的子节点
@export var box_container: Control
## 显示模式
@export_enum("黑名单","白名单") var show_mode:int = 0
## 需要忽略的状态类型。在黑名单模式下启动。
@export var ignore_list:Array[String]
## 需要显示的状态类型。在白名单模式下启动。
@export var pass_list:Array[String]
## 是否在描述控件之间添加线段节点分隔
@export var is_line_division:bool = true

func _ready() -> void:
	_connect_inventory_data_description_signals()
	inventory_data.sorted.connect(_try_update_description)
	_try_update_description()

## 连接背包物品说明所需的细粒度变化信号。
func _connect_inventory_data_description_signals() -> void:
	inventory_data.item_added.connect(_try_update_description)
	inventory_data.item_removed.connect(_try_update_description)
	inventory_data.item_position_changed.connect(_on_inventory_item_position_changed)
	inventory_data.item_rotated.connect(_try_update_description)
	inventory_data.item_reshaped.connect(_try_update_description)
	inventory_data.inventory_cleared.connect(_try_update_description)

## 物品位置变化时刷新说明（忽略 previous_cell 参数）。
func _on_inventory_item_position_changed(_item: ItemInstanceData, _previous_cell: Vector2i) -> void:
	_try_update_description()

## 更新方法，在子类中个体实现
func _try_update_description():
	description_updated.emit()
	clear_all_description()
	for item_instance_data in inventory_data.get_item_instances():
		var panel := VBoxContainer.new()
		if _check_section_type_to_show(ItemDescriptionSectionBuilder.BASE_SECTION_TYPE):
			var base_info_controls := _create_base_info_controls(item_instance_data)
			for base_control in base_info_controls:
				panel.add_child(base_control)
				if is_line_division:
					panel.add_child(HSeparator.new())
		for description_section in ItemDescriptionSectionBuilder.build(item_instance_data):
			var section_type: String = description_section.get("section_type", "")
			if !_check_section_type_to_show(section_type):
				continue
			var controls: Array = description_section.get("controls", [])
			if controls.is_empty():
				continue
			for control in controls:
				panel.add_child(control)
				if is_line_division:
					panel.add_child(HSeparator.new())
		box_container.add_child(panel)

## 清除旧数据
func clear_all_description():
	var children := box_container.get_children()
	for child in children:
		child.queue_free()

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
