class_name InventoryOperationPolicy
extends RefCounted
## 每个执行拥有者独立持有的可选业务策略；永不进入库存存档。
var rules: Array[InventoryOperationRule] = []

## 按功能贡献顺序拼接多份策略的 Rule，供端点持有单一合集。
static func merge(policies: Array) -> InventoryOperationPolicy:
	var result := InventoryOperationPolicy.new()
	for policy in policies:
		if policy == null:
			continue
		for rule in policy.rules:
			result.rules.append(rule)
	return result

func fingerprint() -> int:
	return InventoryOperationFingerprint.of(rules)

func validate() -> StringName:
	for rule in rules:
		if rule == null:
			return &"invalid_operation_rule"
	return &""
