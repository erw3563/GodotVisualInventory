@tool
class_name GridInventoryItemsPanel
extends InventoryItemsPanel
## 背包面板脚本，借助此脚本可以通过鼠标与背包互动。

## 背包网格面板
@export var inventory_grid_panel: InventoryGridPanel:
	set(value):
		_try_disconnect_inventory_grid_panel_signal()
		inventory_grid_panel = value
		if !is_node_ready():
			await ready
		_try_connect_inventory_grid_panel_signal()

#region 网格面板信号
## 连接网格面板的格子尺寸变化信号。
func _try_connect_inventory_grid_panel_signal() -> void:
	if inventory_grid_panel == null:
		return
	if !inventory_grid_panel.cell_size_changed.is_connected(_on_inventory_grid_cell_size_changed):
		inventory_grid_panel.cell_size_changed.connect(_on_inventory_grid_cell_size_changed)
	if !inventory_grid_panel.updated.is_connected(refresh_display):
		inventory_grid_panel.updated.connect(refresh_display)

## 断开网格面板的格子尺寸变化信号。
func _try_disconnect_inventory_grid_panel_signal() -> void:
	if inventory_grid_panel == null:
		return
	if inventory_grid_panel.cell_size_changed.is_connected(_on_inventory_grid_cell_size_changed):
		inventory_grid_panel.cell_size_changed.disconnect(_on_inventory_grid_cell_size_changed)
	if inventory_grid_panel.updated.is_connected(refresh_display):
		inventory_grid_panel.updated.disconnect(refresh_display)

## 格子尺寸变化时刷新全部物品格的大小与位置。
func _on_inventory_grid_cell_size_changed() -> void:
	refresh_display()
#endregion

#region 抽象接口实现
## 根据格子坐标获取物品格在面板中的局部位置。
func _get_pos_by_cell(cell: Vector2i) -> Vector2:
	if inventory_grid_panel == null:
		return Vector2.ZERO
	return inventory_grid_panel.get_cell_local_position(cell)

## 网格背包中物品贴图大小与格子大小一致。
func _get_item_texture_size() -> Vector2:
	if inventory_grid_panel == null:
		return Vector2.ZERO
	return inventory_grid_panel.cell_size

## 网格背包中物品框大小与格子大小一致。
func _get_item_box_size() -> Vector2:
	if inventory_grid_panel == null:
		return Vector2.ZERO
	return inventory_grid_panel.cell_size
#endregion
