@tool
class_name ItemTagOperationRule
extends InventoryOperationRule
## Host 按选择构建的内部规则，不作为物品子资源配置。
@export_storage var tag: String = InventoryItemTags.NO_TAKE

static func create(value: String) -> ItemTagOperationRule:
	var rule := ItemTagOperationRule.new()
	rule.tag = value
	return rule

static func take_denial(item: ItemInstanceData, endpoint: InventoryOperationEndpoint) -> StringName:
	if endpoint == null:
		return &"missing_operation_endpoint"
	if not endpoint.valid or endpoint.policy == null:
		return &"invalid_operation_endpoint"
	var reason := endpoint.policy.validate()
	if reason != &"":
		return reason
	for rule in endpoint.policy.rules:
		if rule is ItemTagOperationRule and rule.tag == InventoryItemTags.NO_TAKE and InventoryItemTags.has_tag(item, rule.tag):
			return &"inventory_leave_blocked"
	return &""

func evaluate(context: InventoryOperationRuleContext) -> InventoryOperationDecision:
	if context == null or context.effect == null:
		return InventoryOperationDecision.allow(context.plan if context != null else null)
	# 完全合并可能没有 ENTER effect，仍需约束进入目标的请求物品。
	var request := context.request
	if tag == InventoryItemTags.NO_PLACE and request != null and context.endpoint != null and context.endpoint == request.operation_context.target_endpoint and request.type in [InventoryOperationRequest.Type.PLACE_AT, InventoryOperationRequest.Type.ADD_WITH_MERGE, InventoryOperationRequest.Type.ADD_WITHOUT_MERGE, InventoryOperationRequest.Type.MERGE_AT, InventoryOperationRequest.Type.REPLACE_AT, InventoryOperationRequest.Type.TRANSFER] and InventoryItemTags.has_tag(request.item, tag):
		return InventoryOperationDecision.reject(&"inventory_enter_blocked")
	var effect := context.effect
	var expected := -1
	var reason: StringName
	match tag:
		InventoryItemTags.NO_TAKE:
			expected = InventoryOperationEffect.Type.LEAVE_INVENTORY
			reason = &"inventory_leave_blocked"
		InventoryItemTags.NO_PLACE:
			expected = InventoryOperationEffect.Type.ENTER_INVENTORY
			reason = &"inventory_enter_blocked"
		InventoryItemTags.NO_CONSUME:
			expected = InventoryOperationEffect.Type.CONSUME_QUANTITY
			reason = &"inventory_consume_blocked"
	if effect.type == expected and InventoryItemTags.has_tag(effect.item, tag):
		return InventoryOperationDecision.reject(reason)
	return InventoryOperationDecision.allow(context.plan)

