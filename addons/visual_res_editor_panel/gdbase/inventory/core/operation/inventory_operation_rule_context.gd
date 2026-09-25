class_name InventoryOperationRuleContext
extends RefCounted

var endpoint: InventoryOperationEndpoint
## Rule 的只读判定上下文。

enum ProviderType {
	CORE,
	SOURCE_INVENTORY,
	TARGET_INVENTORY,
	OPERATION_ITEM,
	AFFECTED_ITEM,
}

var request: InventoryOperationRequest
var plan: InventoryOperationPlan
var provider_type: ProviderType
var provider_inventory: InventoryData
var provider_item: ItemInstanceData
var provider_part: ItemPart
var effect: InventoryOperationEffect
var view: InventoryOperationView
var after_view: InventoryOperationView
## 组合提交最终复核时可用；步骤规划期为 null／空。
var transaction_view: InventoryOperationView
var transaction_effects: Array[InventoryOperationEffect] = []
