class_name InventoryTargetQueryContext
extends RefCounted
## 持有一次库存查询的事实引用与源位置覆盖值。

var inventory: InventoryData
var operation_view: InventoryOperationView
var source: ItemInstanceData
var has_source_cells_override := false
var source_cells: Array[Vector2i] = []:
	set(value):
		source_cells = value.duplicate()
var has_source_direction_override := false
var source_direction := Vector2.RIGHT

static func actual(target_inventory: InventoryData, source_item: ItemInstanceData) -> InventoryTargetQueryContext:
	var context := InventoryTargetQueryContext.new()
	context.inventory = target_inventory
	context.source = source_item
	return context

static func preview(target_inventory: InventoryData, source_item: ItemInstanceData, cells: Array[Vector2i], direction: Vector2) -> InventoryTargetQueryContext:
	var context := actual(target_inventory, source_item)
	context.has_source_cells_override = true
	context.source_cells = cells
	context.has_source_direction_override = true
	context.source_direction = direction
	return context

static func projected(view: InventoryOperationView, source_item: ItemInstanceData) -> InventoryTargetQueryContext:
	var context := InventoryTargetQueryContext.new()
	context.operation_view = view
	context.source = source_item
	return context

func validate() -> StringName:
	if (inventory == null) == (operation_view == null):
		return &"invalid_context"
	if is_projected() and is_preview():
		return &"unsupported_preview"
	return &""

func is_projected() -> bool:
	return operation_view != null

func is_preview() -> bool:
	return has_source_cells_override or has_source_direction_override

func get_items() -> Array[ItemInstanceData]:
	if operation_view != null:
		return operation_view.get_items()
	return inventory.get_item_instances().duplicate() if inventory != null else []

func has_item(item: ItemInstanceData) -> bool:
	if item == null:
		return false
	if operation_view != null:
		return operation_view.has_item(item) and operation_view.get_items().has(item)
	return inventory != null and inventory.has_item_instance(item)

## 按原身份读取本次事实，实际模式返回原实例，预计模式返回隔离副本。
func get_item(item: ItemInstanceData) -> ItemInstanceData:
	if not has_item(item):
		return null
	return operation_view.get_item(item) if operation_view != null else item

func get_cells(item: ItemInstanceData) -> Array[Vector2i]:
	if not has_item(item):
		return []
	if operation_view != null:
		return operation_view.get_cells(item)
	var occupy_map := inventory.get_occupy_map()
	return occupy_map.get_cells_of_occupant(item).duplicate() if occupy_map != null else []

func get_item_at(cell: Vector2i) -> ItemInstanceData:
	if operation_view != null:
		return operation_view.get_item_at(cell)
	var occupy_map := inventory.get_occupy_map() if inventory != null else null
	return occupy_map.get_item_in_cell(cell) if occupy_map != null else null

func is_spatial() -> bool:
	if operation_view != null:
		return operation_view.is_spatial()
	var occupy_map := inventory.get_occupy_map() if inventory != null else null
	return occupy_map != null and occupy_map.is_spatial()

func get_region() -> Array[Vector2i]:
	if operation_view != null:
		return operation_view.get_region()
	var occupy_map := inventory.get_occupy_map() if inventory != null else null
	return occupy_map.cells.duplicate() if occupy_map != null else []

func has_region_cell(cell: Vector2i) -> bool:
	if operation_view != null:
		return operation_view.get_region().has(cell)
	var occupy_map := inventory.get_occupy_map() if inventory != null else null
	return occupy_map != null and occupy_map.has_region_cell(cell)

func get_source_cells() -> Array[Vector2i]:
	if has_source_cells_override:
		return source_cells.duplicate()
	return get_cells(source)

func get_source_direction() -> Vector2:
	if has_source_direction_override:
		return source_direction
	if operation_view != null:
		var fact := get_item(source)
		return fact.dir if fact != null else Vector2.RIGHT
	return source.dir if source != null else Vector2.RIGHT

func validate_spatial() -> StringName:
	var error := validate()
	if error != &"":
		return error
	if source == null:
		return &"invalid_context"
	if not is_spatial():
		return &"spatial_inventory_required"
	if is_projected() and not has_item(source):
		return &"source_item_missing"
	return &""
