@tool
class_name ItemInventoryState
extends ItemInstanceState
## 背包型物品的运行时子背包。有此状态的物品不可堆叠。

const INVENTORY_STATE_KEY := "Inventory"

## 本件持有的子背包数据；实例间隔离，图内允许回边。
@export var nested_inventory_data: InventoryData

func _init() -> void:
	state_key = INVENTORY_STATE_KEY

## 从模板深复制子背包，保证各实例内容独立。
func populate_from_part(inventory_part: ItemInventoryPart) -> void:
	if inventory_part == null or inventory_part.inventory_template == null:
		nested_inventory_data = _create_empty_nested_inventory()
		return
	nested_inventory_data = inventory_part.inventory_template.duplicate_deep(
		Resource.DEEP_DUPLICATE_INTERNAL
	) as InventoryData
	if nested_inventory_data == null:
		nested_inventory_data = _create_empty_nested_inventory()
		return
	nested_inventory_data.ensure_occupancy_synced()

## 创建默认 2x2 空子背包。
func _create_empty_nested_inventory() -> InventoryData:
	var inventory_data := InventoryData.new()
	var cells: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(1, 1),
	]
	inventory_data.init_occupy_map(cells)
	return inventory_data

## 获取本件子背包；缺失时补一个空背包。
func get_nested_inventory_data() -> InventoryData:
	if nested_inventory_data == null:
		nested_inventory_data = _create_empty_nested_inventory()
	return nested_inventory_data

## 深复制时必须连同子背包内容一并复制。
func duplicate_state() -> ItemInstanceState:
	var duplicated := ItemInventoryState.new()
	duplicated.state_key = state_key
	if nested_inventory_data != null:
		duplicated.nested_inventory_data = nested_inventory_data.duplicate_deep(
			Resource.DEEP_DUPLICATE_INTERNAL
		) as InventoryData
		if duplicated.nested_inventory_data != null:
			duplicated.nested_inventory_data.ensure_occupancy_synced()
	else:
		duplicated.nested_inventory_data = _create_empty_nested_inventory()
	return duplicated

## 背包型物品不允许合并，避免吞掉内部物品。
func plan_stack_merge(_context: ItemStackMergeContext) -> ItemStateMergePlan:
	return ItemStateMergePlan.reject(&"nested_inventory_stack_merge_disabled")

## 背包状态类型。
func get_state_type() -> String:
	return INVENTORY_STATE_KEY

## 构建当前子背包描述。
func get_description_panel() -> Array[Control]:
	var result_controls: Array[Control]
	var inventory_data := get_nested_inventory_data()
	var cell_count := 0
	var item_count := 0
	if inventory_data != null:
		if inventory_data.occupy_map != null:
			cell_count = inventory_data.occupy_map.cells.size()
		item_count = inventory_data.get_item_instances().size()
	var label := Label.new()
	label.text = "内嵌背包：%d 格，%d 件" % [cell_count, item_count]
	result_controls.append(label)
	return result_controls
