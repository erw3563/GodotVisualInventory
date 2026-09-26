class_name InventoryReactionProcessor
extends RefCounted
## 响应控制器与无 UI 调用方共用的事务命令入口。
static func prepare(operation_context: InventoryOperationContext, action: ItemReactionAction, inventory: InventoryData, source: ItemInstanceData, random: RandomNumberGenerator = null, trigger: int = -1) -> ItemReactionPlanContext:
	var context := ItemReactionPlanContext.new()
	context.source = source
	context.random = random if random != null else RandomNumberGenerator.new()
	context.trigger_type = trigger
	context._transaction = InventoryOperationTransaction.begin(operation_context, inventory)
	if inventory == null or source == null or not inventory.has_item_instance(source):
		context._transaction.reason_key = &"source_item_missing"
		return context
	var reason := validate_tree(action)
	if reason != &"":
		context._transaction.reason_key = reason
		return context
	context._transaction.guard(action)
	var result := action.plan(context)
	context.plan_result = result
	if result == null:
		context._transaction.reason_key = &"invalid_reaction_result"
	elif not result.is_planned():
		context._transaction.reason_key = result.reason_key
	return context

static func run(operation_context: InventoryOperationContext, action: ItemReactionAction, inventory: InventoryData, source: ItemInstanceData, random: RandomNumberGenerator = null, trigger: int = -1) -> InventoryOperationResult:
	var context := prepare(operation_context, action, inventory, source, random, trigger)
	var result := InventoryOperationCommitter.commit_transaction(context._transaction)
	if context.plan_result != null:
		result.failure_path = context.plan_result.step_path.duplicate()
	return result

static func validate_tree(action: ItemReactionAction) -> StringName:
	return _validate(action, [], [0])

## 归零动作与重置共用一个事务。普通 run(operation_context, action) 不隐含重置。
static func prepare_rule(operation_context: InventoryOperationContext, rule: ItemReactionRule, inventory: InventoryData, source: ItemInstanceData, random: RandomNumberGenerator = null) -> ItemReactionPlanContext:
	var context := ItemReactionPlanContext.new()
	context.source = source
	context.random = random if random != null else RandomNumberGenerator.new()
	context._transaction = InventoryOperationTransaction.begin(operation_context, inventory)
	if context._transaction.reason_key != &"":
		return context
	if rule == null or source == null or not inventory.has_item_instance(source):
		context._transaction.reason_key = &"source_item_missing"
		return context
	context.trigger_type = rule.trigger_type
	var reason := rule.validate_configuration(source.item_data)
	if reason == &"":
		reason = ItemReactionRule.validate_counter_rules(source.item_data)
	if reason != &"":
		context._transaction.reason_key = reason
		return context
	context._transaction.guard(rule)
	var part: ItemCounterPart
	if rule.trigger_type == ItemReactionRule.TriggerType.COUNTER_ZERO:
		part = ItemCounterPart.find(source.item_data, rule.counter_key)
		var projected := context.view.get_item(source)
		var state := part.resolve_state(projected)
		if state == null or not state.reconcile_with_part(part) or state.current_value != 0:
			context._transaction.reason_key = &"counter_not_ready"
			return context
		context._transaction.guard(part)
		context.protected_counter_item = source
		context.protected_counter_key = rule.counter_key
	var result := rule.action.plan(context)
	context.plan_result = result
	if result == null:
		context._transaction.reason_key = &"invalid_reaction_result"
	elif not result.is_planned():
		context._transaction.reason_key = result.reason_key
	elif part != null:
		if not context.view.has_item(source):
			context._transaction.reason_key = &"trigger_counter_source_removed"
			return context
		var projected := context.view.get_item(source)
		var state := part.resolve_state(projected)
		if state == null or state.current_value != 0:
			context._transaction.reason_key = &"trigger_counter_write_forbidden"
			return context
		# 只有编排器能解除本轮写保护并追加重置，Action 不接管提交。
		context.protected_counter_item = null
		state.current_value = part.initial_value
		var reset := context.append(InventoryOperationRequest.Type.UPDATE_STATES, source, -1, Vector2i(-1, -1), null, projected.instance_states)
		if not reset.is_planned():
			context._transaction.reason_key = reset.reason_key
	return context

static func run_rule(operation_context: InventoryOperationContext, rule: ItemReactionRule, inventory: InventoryData, source: ItemInstanceData, random: RandomNumberGenerator = null) -> InventoryOperationResult:
	var context := prepare_rule(operation_context, rule, inventory, source, random)
	var result := InventoryOperationCommitter.commit_transaction(context._transaction)
	if context.plan_result != null:
		result.failure_path = context.plan_result.step_path.duplicate()
	return result

static func _validate(action: ItemReactionAction, ancestors: Array, count: Array[int]) -> StringName:
	if action == null:
		return &"missing_reaction_action"
	if ancestors.has(action):
		return &"reaction_action_cycle"
	if ancestors.size() >= 16 or count[0] >= 128:
		return &"reaction_action_limit"
	count[0] += 1
	var reason := action.validate_configuration()
	if reason != &"":
		return reason
	ancestors.append(action)
	for child in action.get_child_actions():
		reason = _validate(child, ancestors, count)
		if reason != &"":
			return reason
	ancestors.pop_back()
	return &""
