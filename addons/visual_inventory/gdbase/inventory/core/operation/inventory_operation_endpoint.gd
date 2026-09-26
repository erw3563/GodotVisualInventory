class_name InventoryOperationEndpoint
extends RefCounted
## 独占运行时端点；同库存可有任意多个不同策略端点。
var inventory: InventoryData
var policy: InventoryOperationPolicy
var valid := true
var generation := 0

static func create(target: InventoryData, rules_policy: InventoryOperationPolicy) -> InventoryOperationEndpoint:
	var endpoint := InventoryOperationEndpoint.new()
	endpoint.inventory = target
	endpoint.policy = rules_policy
	return endpoint

func invalidate() -> void:
	valid = false
	generation += 1

func fingerprint() -> int:
	return hash([get_instance_id(), inventory, valid, generation, policy.fingerprint() if policy != null else 0])

func validate(target: InventoryData) -> StringName:
	if not valid or inventory == null or inventory != target or policy == null:
		return &"invalid_operation_endpoint"
	return policy.validate()
