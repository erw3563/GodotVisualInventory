class_name InventoryOperationPlan
extends RefCounted
## Planner 生成的只读候选方案。方案只可成功提交一次。

var policy_signature: int = 0
var request: InventoryOperationRequest
var effects: Array[InventoryOperationEffect] = []
var inventory_revisions: Dictionary = {}
var item_snapshots: Dictionary = {}
var actual_quantity: int = 0
var replaced_item: ItemInstanceData
var output_item: ItemInstanceData
## 部分放入／转移在规划期创建的未归属实例；提交前不会进入库存或手持会话。
var pending_item: ItemInstanceData
## 精确数量对应的 Item State 变换；提交前会基于当前事实整体重规划。
var stack_plans: Array[ItemStackOperationPlan] = []
## 批量重排的最终格位与朝向，键为原物品实例。
var layout_targets: Dictionary = {}
var used: bool = false
## Rule 始终使用原实例身份，通过视图读取预计事实。
var view: InventoryOperationView
var after_view: InventoryOperationView
var transaction_view: InventoryOperationView
var transaction_effects: Array[InventoryOperationEffect] = []
var prepared_state_results: Array[ItemInstanceState] = []
var requested_states_signature: int = 0
var prepared_states_signature: int = 0


func add_effect(effect: InventoryOperationEffect) -> void:
	if effect != null:
		effects.append(effect)


func capture_inventory(inventory: InventoryData) -> void:
	if inventory != null and !inventory_revisions.has(inventory):
		inventory_revisions[inventory] = inventory.revision


func capture_item(item: ItemInstanceData, inventory: InventoryData = null) -> void:
	if item == null or item_snapshots.has(item):
		return
	var cell := Vector2i(-1, -1)
	if inventory != null and inventory.occupy_map != null and inventory.has_item_instance(item):
		cell = inventory.occupy_map.get_item_center_cell(item)
	item_snapshots[item] = {
		"quantity": item.get_item_num(),
		"dir": item.dir,
		"cell": cell,
		"inventory": inventory,
		"shape": item.get_local_cells(),
		"states_hash": InventoryOperationFingerprint.of(item.instance_states),
		"item_data": item.item_data,
		"item_data_hash": InventoryOperationFingerprint.of(item.item_data),
	}


func get_effects_of_type(effect_type: InventoryOperationEffect.Type) -> Array[InventoryOperationEffect]:
	var result: Array[InventoryOperationEffect] = []
	for effect in effects:
		if effect != null and effect.type == effect_type:
			result.append(effect)
	return result
