@tool
class_name ItemInventoryPart
extends ItemPart
## 背包型物品拼图。模板描述子背包容量与静态面板样式；运行时内容由实例状态持有。

const INVENTORY_PART_TYPE := "Inventory"

## 子背包模板（通常只含占位图，可含初始物品）。实例化时会深复制。
@export var inventory_template: InventoryData
## 本类物品的子库存面板定义；打开时必须显式配置，不隐式回退 GRID。
@export var nested_panel_definition: InventoryPanelAssemblyDefinition

static func get_part_type() -> String:
	return INVENTORY_PART_TYPE

func allows_multiple() -> bool:
	return false

## 默认使用固定状态键，保证存档与补齐对齐。
func get_instance_state_key() -> String:
	if !instance_state_key.is_empty():
		return instance_state_key
	return "Inventory"

## 创建本件运行时子背包状态。
func create_instance_state() -> ItemInstanceState:
	var inventory_state := ItemInventoryState.new()
	inventory_state.state_key = get_instance_state_key()
	inventory_state.populate_from_part(self)
	return inventory_state

## 从物品实例解析本 Part 对应的内嵌背包状态。
func resolve_state(item_instance: ItemInstanceData) -> ItemInventoryState:
	if item_instance == null:
		return null
	return item_instance.get_state_by_key(get_instance_state_key()) as ItemInventoryState

## 查询本件声明的子库存；缺失 State 或空引用关闭失败。
func query_owned_inventories(item_instance: ItemInstanceData) -> NestedInventoryQueryResult:
	if item_instance == null:
		return NestedInventoryQueryResult.failure()
	var inventory_state := item_instance.peek_state_by_key(
		get_instance_state_key()
	) as ItemInventoryState
	if inventory_state == null or inventory_state.nested_inventory_data == null:
		return NestedInventoryQueryResult.failure()
	return NestedInventoryQueryResult.success([inventory_state.nested_inventory_data])

## 构建背包型物品描述。
func get_description_panel() -> Array[Control]:
	var result_controls: Array[Control]
	var label := Label.new()
	var cell_count := 0
	if inventory_template != null and inventory_template.occupy_map != null:
		cell_count = inventory_template.occupy_map.cells.size()
	label.text = "内嵌背包：%d 格" % cell_count
	result_controls.append(label)
	return result_controls
