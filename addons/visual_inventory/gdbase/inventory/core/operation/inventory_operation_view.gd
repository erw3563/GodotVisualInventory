class_name InventoryOperationView
extends RefCounted
## 库存预计事实的只读查询。返回实例副本，身份查询始终使用原实例。
var _inventory: InventoryData
var _actual_to_virtual: Dictionary = {}
var _virtual_to_actual: Dictionary = {}

func get_items() -> Array[ItemInstanceData]:
	var result: Array[ItemInstanceData] = []
	for item in _inventory.get_item_instances():
		result.append(_virtual_to_actual.get(item, item))
	return result

func has_item(item: ItemInstanceData) -> bool:
	return _inventory.has_item_instance(_actual_to_virtual.get(item, item))

func get_item(item: ItemInstanceData) -> ItemInstanceData:
	var projected: ItemInstanceData = _actual_to_virtual.get(item, item)
	if projected == null:
		return null
	var copy := projected.duplicate_for_operation()
	copy.num = projected.num
	return copy

func get_cell(item: ItemInstanceData) -> Vector2i:
	return _inventory.occupy_map.get_item_center_cell(_actual_to_virtual.get(item, item))

func get_cells(item: ItemInstanceData) -> Array[Vector2i]:
	return _inventory.occupy_map.get_cells_of_occupant(_actual_to_virtual.get(item, item)).duplicate()

func get_region() -> Array[Vector2i]:
	return _inventory.occupy_map.cells.duplicate()

func get_item_at(cell: Vector2i) -> ItemInstanceData:
	var item := _inventory.occupy_map.get_item_in_cell(cell)
	return _virtual_to_actual.get(item, item)

func is_spatial() -> bool:
	return _inventory.occupy_map.is_spatial()
