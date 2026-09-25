class_name InventoryContainmentCycleRule
extends InventoryOperationRule
## 嵌套库存防环：目标端点可选策略，拒绝进入影响形成子库存所有权环。


func evaluate(context: InventoryOperationRuleContext) -> InventoryOperationDecision:
	if context == null or context.plan == null:
		return InventoryOperationDecision.reject(&"invalid_operation_context")
	var effects := context.transaction_effects if not context.transaction_effects.is_empty() else context.plan.effects
	for effect in effects:
		if effect == null:
			continue
		if context.endpoint != null and effect.inventory != null and effect.inventory != context.endpoint.inventory:
			continue
		match effect.type:
			InventoryOperationEffect.Type.ENTER_INVENTORY:
				var enter_decision := evaluate_item_entry(_resolve_item(effect.item, context), effect.inventory)
				if not enter_decision.allowed:
					return enter_decision
			InventoryOperationEffect.Type.CHANGE_STATES:
				var state_decision := evaluate_item_entry(_item_for_state_change(effect.item, context), effect.inventory)
				if not state_decision.allowed:
					return state_decision
	return InventoryOperationDecision.allow(context.plan)


func evaluate_item_entry(item: ItemInstanceData, target_inventory: InventoryData) -> InventoryOperationDecision:
	if item == null or target_inventory == null:
		return InventoryOperationDecision.reject(&"invalid_inventory_ownership")
	var pending_items: Array[ItemInstanceData] = [item]
	var visited_inventories: Dictionary = {}
	var visited_items: Dictionary = {}
	while not pending_items.is_empty():
		var current_item: ItemInstanceData = pending_items.pop_front()
		if current_item == null or visited_items.has(current_item):
			continue
		visited_items[current_item] = true
		var ownership := NestedInventoryQuery.query_owned_inventories(current_item)
		if not ownership.valid:
			return InventoryOperationDecision.reject(&"invalid_inventory_ownership")
		for owned_inventory in ownership.inventories:
			if owned_inventory == null:
				return InventoryOperationDecision.reject(&"invalid_inventory_ownership")
			if owned_inventory == target_inventory:
				return InventoryOperationDecision.reject(&"nested_inventory_cycle")
			if visited_inventories.has(owned_inventory):
				continue
			visited_inventories[owned_inventory] = true
			for child_item in owned_inventory.get_item_instances():
				if child_item != null:
					pending_items.append(child_item)
	return InventoryOperationDecision.allow()


func _item_for_state_change(item: ItemInstanceData, context: InventoryOperationRuleContext) -> ItemInstanceData:
	if item == null:
		return null
	if context.plan != null and context.plan.request != null and context.plan.request.item == item \
			and not context.plan.prepared_state_results.is_empty():
		var projected := item.duplicate_for_operation()
		projected.instance_states = context.plan.prepared_state_results
		return projected
	return _resolve_item(item, context)


func _resolve_item(item: ItemInstanceData, context: InventoryOperationRuleContext) -> ItemInstanceData:
	if item == null or context == null:
		return item
	var view := context.transaction_view if context.transaction_view != null else context.after_view
	if view == null:
		return item
	var projected := view.get_item(item)
	return projected if projected != null else item
