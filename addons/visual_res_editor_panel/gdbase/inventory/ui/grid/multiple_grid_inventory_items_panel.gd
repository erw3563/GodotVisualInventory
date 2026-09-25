class_name MultipleGridInventoryItemsPanel
extends GridInventoryItemsPanel
## 多重背包面板，内含多个背包数据 InventoryData 与一个背包网格面板，同一时刻只会显示一个背包内容。通过按钮节点来切换显示的背包数据，一个按钮对应一个背包数据。

## 背包切换后发出，参数为切换后的背包下标和背包数据。
signal show_inventory_data_changed(inventory_data:InventoryData)
signal show_new_data
signal show_showing_data

## 总背包面板
@export var inventory_data_list:Array[InventoryData]
## 库存数据切换按钮容器
@export var data_button_container:Control
var data_buttons:Array[Button] = []


func _ready() -> void:
	_refresh_data_buttons()
	if !inventory_data_list.is_empty():
		select_inventory_to_show(inventory_data_list.front())
	super._ready()

func add_inventory_data(inventroy:InventoryData):
	inventory_data_list.append(inventroy)
	_refresh_data_buttons()

## 按背包数据切换当前显示背包，找不到时返回 false。
func select_inventory_to_show(inventory_data_to_show:InventoryData):
	if inventory_data_to_show != inventory_data:
		inventory_data = inventory_data_to_show
		_sync_inventory_items_input_controller_inventory_data()
		show_inventory_data_changed.emit(inventory_data_to_show)
		show_new_data.emit()
	else:
		show_showing_data.emit()

## 返回当前显示的背包数据。
func get_current_inventory_data() -> InventoryData:
	return inventory_data

## 收集并连接按钮容器中的按钮。
func _refresh_data_buttons() -> void:
	data_buttons.map(func(node:Node):node.queue_free())
	data_buttons.clear()
	if data_button_container == null:
		return

	for inventory_data_in_list in inventory_data_list:
		var button := Button.new()
		button.custom_minimum_size = Vector2(154,32)
		button.button_up.connect(select_inventory_to_show.bind(inventory_data_in_list))
		data_button_container.add_child.call_deferred(button)

## 将子节点上的输入控制器与本面板当前展示的背包数据对齐。
func _sync_inventory_items_input_controller_inventory_data() -> void:
	for child_node in get_children():
		if child_node is InventoryItemsInputController:
			child_node.inventory_data = inventory_data
