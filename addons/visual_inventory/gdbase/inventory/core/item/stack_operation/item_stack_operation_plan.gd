class_name ItemStackOperationPlan
extends RefCounted
## 完整 Item 级堆叠变换结果。规划成功前不修改任何输入对象。

enum Type {
	MERGE,
	SPLIT,
}

var allowed: bool = false
var reason_key: StringName
var type: Type
var target_item: ItemInstanceData
var source_item: ItemInstanceData
var target_num_before: int = 0
var source_num_before: int = 0
var target_num_after: int = 0
var source_num_after: int = 0
var transfer_num: int = 0
var target_states: Array[ItemInstanceState] = []
var source_states: Array[ItemInstanceState] = []
var target_state_fact_hashes: Dictionary = {}
var source_state_fact_hashes: Dictionary = {}
var item_data_fact_hash: int = 0


static func reject(reason: StringName) -> ItemStackOperationPlan:
	var plan := ItemStackOperationPlan.new()
	plan.reason_key = reason
	return plan


func capture_facts() -> void:
	target_state_fact_hashes = _hash_states(target_item.instance_states) if target_item != null else {}
	source_state_fact_hashes = _hash_states(source_item.instance_states) if source_item != null else {}
	if target_item != null and target_item.item_data != null:
		item_data_fact_hash = hash(var_to_bytes_with_objects(target_item.item_data))


func matches_current_facts() -> bool:
	if target_item == null or target_item.num != target_num_before:
		return false
	if _hash_states(target_item.instance_states) != target_state_fact_hashes:
		return false
	if target_item.item_data == null \
			or hash(var_to_bytes_with_objects(target_item.item_data)) != item_data_fact_hash:
		return false
	if type == Type.MERGE:
		if source_item == null or source_item.num != source_num_before:
			return false
		if source_item.item_data != target_item.item_data:
			return false
		if _hash_states(source_item.instance_states) != source_state_fact_hashes:
			return false
	return true


static func _hash_states(states: Array[ItemInstanceState]) -> Dictionary:
	var result: Dictionary = {}
	for state in states:
		if state == null or state.state_key.is_empty() or result.has(state.state_key):
			return {}
		result[state.state_key] = hash(var_to_bytes_with_objects(state))
	return result
