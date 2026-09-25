class_name InventoryOperationCommitter
extends RefCounted
static var _publishing: Dictionary = {}
## 管理快照和其它观察者不得在事务发布到一半时读取候选事实。
static func is_publishing(inventory: InventoryData) -> bool:
	return _publishing.has(inventory)

## 玩法库存变化的唯一提交入口。


static func commit(candidate: InventoryOperationPlan) -> InventoryOperationResult:
	if candidate != null:
		for inventory in candidate.inventory_revisions:
			if _publishing.has(inventory):
				return InventoryOperationResult.failed(&"inventory_transaction_reentry", candidate)
	var stale_reason := _validate_fresh(candidate)
	if stale_reason != &"":
		return InventoryOperationResult.failed(stale_reason, candidate)
	var stack_prepare_reason := _prepare_stack_plans(candidate)
	if stack_prepare_reason != &"":
		return InventoryOperationResult.failed(stack_prepare_reason, candidate)
	var rule_decision := InventoryOperationPlanner.evaluate_rules(candidate)
	if !rule_decision.allowed:
		return InventoryOperationResult.failed(rule_decision.reason_key, candidate)
	var snapshots: Dictionary = {}
	var affected: Array = candidate.item_snapshots.keys()
	if candidate.pending_item != null and not affected.has(candidate.pending_item):
		affected.append(candidate.pending_item)
	for inventory in candidate.inventory_revisions:
		snapshots[inventory] = _save_publication(inventory, affected)
	for inventory in snapshots:
		_publishing[inventory] = true
		_block_publication(snapshots[inventory])
	var committed := _commit_by_type(candidate)
	if !committed:
		for inventory in snapshots:
			_restore_publication(inventory, snapshots[inventory])
		# 两端快照共享受影响实例；全部恢复结束后才解除信号屏蔽。
		for inventory in snapshots:
			_restore_signal_flags(snapshots[inventory])
			_publishing.erase(inventory)
		return InventoryOperationResult.failed(&"operation_commit_failed", candidate)
	for inventory in snapshots:
		_restore_signal_flags(snapshots[inventory])
	candidate.used = true
	for inventory in candidate.inventory_revisions.keys():
		var inventory_data := inventory as InventoryData
		inventory_data._advance_operation_revision()
	_emit_effect_signals(candidate)
	for inventory in candidate.inventory_revisions.keys():
		var inventory_data := inventory as InventoryData
		inventory_data.ensure_occupancy_synced()
		inventory_data._emit_operation_committed(candidate)
	for inventory in snapshots:
		_publishing.erase(inventory)
	return InventoryOperationResult.succeeded(candidate)


static func _emit_effect_signals(candidate: InventoryOperationPlan) -> void:
	for effect in candidate.effects:
		if effect == null or effect.item == null:
			continue
		match effect.type:
			InventoryOperationEffect.Type.CHANGE_QUANTITY:
				effect.item.num_changed.emit(effect.item.num)
			InventoryOperationEffect.Type.LEAVE_INVENTORY, \
			InventoryOperationEffect.Type.DESTROY_ITEM:
				if effect.removes_membership and effect.inventory != null \
						and effect.inventory.occupy_map != null:
					effect.inventory.occupy_map.item_instance_removed.emit(
						effect.item, effect.cell_before
					)
			InventoryOperationEffect.Type.ENTER_INVENTORY:
				if effect.inventory != null and effect.inventory.occupy_map != null:
					effect.inventory.occupy_map.item_instance_added.emit(effect.item)
			InventoryOperationEffect.Type.CHANGE_POSITION:
				if effect.inventory != null and effect.inventory.occupy_map != null:
					effect.inventory.occupy_map.item_instance_position_changed.emit(
						effect.item, effect.cell_before
					)
			InventoryOperationEffect.Type.CHANGE_ROTATION:
				effect.item.dir_changed.emit(effect.item.dir)
				if effect.inventory != null and effect.inventory.occupy_map != null:
					effect.inventory.occupy_map.item_instance_rotated.emit(effect.item)
			InventoryOperationEffect.Type.CHANGE_SHAPE:
				effect.item.shape_changed.emit()
				if effect.inventory != null and effect.inventory.occupy_map != null:
					effect.inventory.occupy_map.item_instance_reshaped.emit(effect.item)


static func _validate_fresh(candidate: InventoryOperationPlan) -> StringName:
	if candidate == null or candidate.request == null:
		return &"invalid_operation_plan"
	if candidate.policy_signature != 0 and (candidate.request.operation_context == null or candidate.request.operation_context.fingerprint() != candidate.policy_signature):
		return &"stale_operation_policy"
	if candidate.used:
		return &"operation_plan_already_used"
	if candidate.request.type == InventoryOperationRequest.Type.UPDATE_STATES and InventoryOperationFingerprint.of(candidate.request.state_results) != candidate.requested_states_signature:
		return &"stale_operation_plan"
	if candidate.request.type == InventoryOperationRequest.Type.RESHAPE:
		if InventoryOperationFingerprint.of(candidate.request.shape_result) != candidate.requested_states_signature \
			or InventoryOperationFingerprint.of(candidate.prepared_state_results) != candidate.prepared_states_signature:
			return &"stale_operation_plan"
	for inventory in candidate.inventory_revisions.keys():
		if inventory == null or (inventory as InventoryData).revision != candidate.inventory_revisions[inventory]:
			return &"stale_operation_plan"
	for item in candidate.item_snapshots.keys():
		if item == null:
			return &"stale_operation_plan"
		var snapshot: Dictionary = candidate.item_snapshots[item]
		if item.get_item_num() != snapshot.quantity or item.dir != snapshot.dir:
			return &"stale_operation_plan"
		if item.get_local_cells() != snapshot.shape:
			return &"stale_operation_plan"
		if InventoryOperationFingerprint.of(item.instance_states) != snapshot.states_hash:
			return &"stale_operation_plan"
		if item.item_data != snapshot.item_data \
				or InventoryOperationFingerprint.of(item.item_data) != snapshot.item_data_hash:
			return &"stale_operation_plan"
		var inventory: InventoryData = snapshot.inventory
		if inventory != null:
			if !inventory.has_item_instance(item):
				return &"stale_operation_plan"
			if inventory.occupy_map.get_item_center_cell(item) != snapshot.cell:
				return &"stale_operation_plan"
	return &""


static func _commit_by_type(candidate: InventoryOperationPlan) -> bool:
	var request := candidate.request
	match request.type:
		InventoryOperationRequest.Type.CONSUME:
			if candidate.actual_quantity < request.item.num:
				return ItemStackOperationCommitter.apply_prepared_split(candidate.stack_plans[0]) != null
			return request.source_inventory.occupy_map.try_take_item_instance(request.item)
		InventoryOperationRequest.Type.UPDATE_STATES:
			request.item.instance_states = candidate.prepared_state_results
			request.item._mark_instance_states_ready()
			return true
		InventoryOperationRequest.Type.TAKE:
			if candidate.actual_quantity < request.item.get_item_num():
				if candidate.stack_plans.size() != 1:
					return false
				candidate.output_item = ItemStackOperationCommitter.apply_prepared_split(
					candidate.stack_plans[0]
				)
				return candidate.output_item != null
			candidate.output_item = request.item
			return request.source_inventory.occupy_map.try_take_item_instance(request.item)
		InventoryOperationRequest.Type.DESTROY:
			# 占用写入复用精确成员移除；销毁语义由独立 Effect 与空 output_item 表达。
			return request.source_inventory.occupy_map.try_take_item_instance(request.item)
		InventoryOperationRequest.Type.PLACE_AT:
			if !_commit_pending_split(candidate):
				return false
			var placed_item: ItemInstanceData = candidate.pending_item \
				if candidate.pending_item != null else request.item
			return request.target_inventory.occupy_map.try_place_item_instance_in_cell(
				placed_item, request.target_cell
			)
		InventoryOperationRequest.Type.ADD_WITHOUT_MERGE:
			return _commit_enter_effect(candidate)
		InventoryOperationRequest.Type.ADD_WITH_MERGE:
			return _commit_add_with_merge(candidate, false)
		InventoryOperationRequest.Type.MERGE_AT:
			return _commit_merge(candidate)
		InventoryOperationRequest.Type.REPLACE_AT:
			return request.target_inventory.occupy_map.try_replace_item_instance_in_cell(
				request.item, request.target_cell
			) == candidate.replaced_item
		InventoryOperationRequest.Type.MOVE_WITHIN:
			return request.source_inventory.occupy_map.try_move_item_instance_to_cell(
				request.item, request.target_cell
			)
		InventoryOperationRequest.Type.ROTATE:
			return request.source_inventory.occupy_map.try_rotate_item_instance(
				request.item, request.rotate_step
			)
		InventoryOperationRequest.Type.RESHAPE:
			return request.source_inventory.occupy_map.try_reshape_item_instance(
				request.item, candidate.prepared_state_results
			)
		InventoryOperationRequest.Type.TRANSFER:
			return _commit_add_with_merge(candidate, true)
		InventoryOperationRequest.Type.RELAYOUT:
			return _commit_relayout(candidate)
	return false


static func _commit_enter_effect(candidate: InventoryOperationPlan) -> bool:
	for effect in candidate.effects:
		if effect.type != InventoryOperationEffect.Type.ENTER_INVENTORY:
			continue
		return effect.inventory.occupy_map.try_register_item_instance_at_placement(
			effect.item, effect.cell_after, effect.dir_after
		)
	return false


static func _commit_merge(candidate: InventoryOperationPlan) -> bool:
	var request := candidate.request
	var target_item := request.target_inventory.occupy_map.get_item_in_cell(request.target_cell)
	if target_item == null or !_commit_pending_split(candidate):
		return false
	var merge_plan := _get_stack_plan(candidate, ItemStackOperationPlan.Type.MERGE)
	if merge_plan == null or !ItemStackOperationCommitter.apply_prepared_merge(merge_plan):
		return false
	var merged_item: ItemInstanceData = candidate.pending_item \
		if candidate.pending_item != null else request.item
	if merged_item.num == 0 and request.target_inventory.has_item_instance(merged_item):
		return request.target_inventory.occupy_map.try_take_item_instance(merged_item)
	return true


static func _commit_add_with_merge(candidate: InventoryOperationPlan, is_transfer: bool) -> bool:
	var request := candidate.request
	var source := request.source_inventory if is_transfer else null
	if !_commit_pending_split(candidate):
		return false
	var operation_item: ItemInstanceData = candidate.pending_item \
		if candidate.pending_item != null else request.item
	var original_quantity: int = operation_item.num
	for stack_plan in candidate.stack_plans:
		if stack_plan.type == ItemStackOperationPlan.Type.SPLIT:
			continue
		if !ItemStackOperationCommitter.apply_prepared_merge(stack_plan):
			return false
	var has_enter := false
	for effect in candidate.effects:
		if effect.type == InventoryOperationEffect.Type.ENTER_INVENTORY \
				and effect.item == operation_item:
			has_enter = true
			if !effect.inventory.occupy_map.try_register_item_instance_at_placement(
				operation_item, effect.cell_after, effect.dir_after
			):
				return false
	if is_transfer and candidate.pending_item == null:
		if !source.occupy_map.try_take_item_instance(request.item):
			return false
	if !has_enter and operation_item.num > 0:
		return false
	if is_transfer:
		candidate.output_item = operation_item
	return original_quantity - operation_item.num >= 0


static func _commit_pending_split(candidate: InventoryOperationPlan) -> bool:
	if candidate.pending_item == null:
		return true
	var split_plan := _get_stack_plan(candidate, ItemStackOperationPlan.Type.SPLIT)
	return split_plan != null and ItemStackOperationCommitter.apply_prepared_split_into(
		split_plan, candidate.pending_item
	)


static func _get_stack_plan(
	candidate: InventoryOperationPlan, stack_type: ItemStackOperationPlan.Type
) -> ItemStackOperationPlan:
	for stack_plan in candidate.stack_plans:
		if stack_plan != null and stack_plan.type == stack_type:
			return stack_plan
	return null


## 在任何真实写入前，用当前事实和虚拟副本准备整项操作的全部 State 结果。
static func _prepare_stack_plans(candidate: InventoryOperationPlan) -> StringName:
	if candidate.stack_plans.is_empty():
		return &""
	var virtual_by_actual: Dictionary = {}
	var prepared: Array[ItemStackOperationPlan] = []
	for expected in candidate.stack_plans:
		if expected == null or !expected.allowed:
			return &"invalid_stack_operation_plan"
		var actual_target := expected.target_item
		if actual_target == null:
			return &"invalid_stack_operation_plan"
		var virtual_target := _get_virtual_item(actual_target, virtual_by_actual)
		if expected.type == ItemStackOperationPlan.Type.SPLIT:
			var split_plan := ItemStackOperationPlanner.plan_split(
				virtual_target, expected.transfer_num
			)
			if !split_plan.allowed:
				return split_plan.reason_key
			var actual_split_plan := _retarget_stack_plan(
				split_plan, actual_target, null
			)
			prepared.append(actual_split_plan)
			var virtual_split := ItemStackOperationCommitter.apply_prepared_split(split_plan)
			if virtual_split == null:
				return &"invalid_stack_state_result"
			if candidate.pending_item != null and actual_target == candidate.request.item:
				virtual_by_actual[candidate.pending_item] = virtual_split
			continue
		var actual_source := expected.source_item
		if actual_source == null:
			return &"invalid_stack_operation_plan"
		var virtual_source := _get_virtual_item(actual_source, virtual_by_actual)
		var merge_plan := ItemStackOperationPlanner.plan_merge(
			virtual_target, virtual_source, expected.transfer_num
		)
		if !merge_plan.allowed:
			return merge_plan.reason_key
		var actual_merge_plan := _retarget_stack_plan(
			merge_plan, actual_target, actual_source
		)
		prepared.append(actual_merge_plan)
		if !ItemStackOperationCommitter.apply_prepared_merge(merge_plan):
			return &"invalid_stack_state_result"
	candidate.stack_plans = prepared
	return &""


static func _get_virtual_item(
	actual: ItemInstanceData, virtual_by_actual: Dictionary
) -> ItemInstanceData:
	if virtual_by_actual.has(actual):
		return virtual_by_actual[actual]
	var virtual := actual.duplicate_for_operation()
	virtual_by_actual[actual] = virtual
	return virtual


static func _retarget_stack_plan(
	virtual_plan: ItemStackOperationPlan,
	target_item: ItemInstanceData,
	source_item: ItemInstanceData
) -> ItemStackOperationPlan:
	var plan := ItemStackOperationPlan.new()
	plan.allowed = virtual_plan.allowed
	plan.reason_key = virtual_plan.reason_key
	plan.type = virtual_plan.type
	plan.target_item = target_item
	plan.source_item = source_item
	plan.target_num_before = virtual_plan.target_num_before
	plan.source_num_before = virtual_plan.source_num_before
	plan.target_num_after = virtual_plan.target_num_after
	plan.source_num_after = virtual_plan.source_num_after
	plan.transfer_num = virtual_plan.transfer_num
	plan.target_states = virtual_plan.target_states
	plan.source_states = virtual_plan.source_states
	return plan


static func _commit_relayout(candidate: InventoryOperationPlan) -> bool:
	var inventory := candidate.request.source_inventory
	var occupy_map := inventory.occupy_map
	occupy_map.clear_occupancy()
	for item in candidate.layout_targets.keys():
		var target: Dictionary = candidate.layout_targets[item]
		if !occupy_map.try_register_item_instance_at_placement(
			item as ItemInstanceData, target.cell, target.dir
		):
			return false
	return true

## 仅供隔离工作区初始化，不发布真实库存事件。
static func seed_projection(inventory: InventoryData, item: ItemInstanceData, cell: Vector2i) -> void:
	inventory.occupy_map.try_register_item_instance_at_placement(item, cell, item.dir)
	inventory.ensure_occupancy_synced()

## 单库存多步骤唯一提交入口：重放预检、保留身份、整体发布。
## finalize 在库存静默写入后、任何通知前同步执行。必须返回 bool，不得 await 或发通知；
## false 时自行恢复外域写入，本提交器恢复库存。用于跨域原子提交，不持有业务知识。
static func commit_transaction(tx: InventoryOperationTransaction, finalize: Callable = Callable()) -> InventoryOperationResult:
	if tx == null:
		return InventoryOperationResult.failed(&"invalid_transaction")
	var stale := tx.validate_fresh()
	if stale != &"":
		return InventoryOperationResult.failed(stale)
	if _publishing.has(tx.inventory):
		return InventoryOperationResult.failed(&"inventory_transaction_reentry")
	if tx.steps.is_empty():
		return InventoryOperationResult.failed(&"empty_transaction")
	var fresh := tx.replay()
	if fresh.reason_key != &"":
		return InventoryOperationResult.failed(fresh.reason_key)
	var all_effects: Array[InventoryOperationEffect] = []
	for step in fresh.rule_plans:
		all_effects.append_array(step.effects)
	var final_view := fresh._snapshot_view()
	for step in fresh.rule_plans:
		step.transaction_view = final_view
		step.transaction_effects = all_effects
		var final_decision := InventoryOperationPlanner.evaluate_rules(step)
		if not final_decision.allowed:
			return InventoryOperationResult.failed(final_decision.reason_key)
	for actual: ItemInstanceData in fresh._state_changed:
		var prepared: Array[ItemInstanceState] = []
		var projected: ItemInstanceData = fresh._actual_to_virtual[actual]
		for state in projected.instance_states:
			var previous: ItemInstanceState = actual.get_state_by_key(state.state_key)
			if not fresh._replace_all_states.has(actual) and previous != null and InventoryOperationFingerprint.of(previous) == InventoryOperationFingerprint.of(state):
				prepared.append(previous)
			else:
				var copy := state.duplicate_for_operation()
				if copy == null or copy == state or copy.state_key != state.state_key or copy.get_script() != state.get_script():
					return InventoryOperationResult.failed(&"invalid_state_results")
				prepared.append(copy)
		fresh._prepared_states[actual] = prepared
	# Rule/State 扩展必须纯查询；再次核对以关闭非法扩展修改事实的窗口。
	stale = tx.validate_fresh()
	if stale != &"":
		return InventoryOperationResult.failed(stale)
	var inventory := tx.inventory
	var saved := _save_publication(inventory, fresh._actual_to_virtual.keys())
	var result_plan := _build_transaction_result(fresh)
	_publishing[inventory] = true
	_block_publication(saved)
	var succeeded := _publish_projection(fresh)
	if succeeded and finalize.is_valid():
		succeeded = finalize.call() == true
	if not succeeded:
		_restore_publication(inventory, saved)
		_restore_signal_flags(saved)
		_publishing.erase(inventory)
		return InventoryOperationResult.failed(&"operation_commit_failed")
	tx.used = true
	result_plan.used = true
	inventory._advance_operation_revision()
	_restore_signal_flags(saved)
	# 缓存已同步，因此直接转发 InventoryData 的事件，避免 added 被缓存去重吞掉。
	for effect in result_plan.effects:
		match effect.type:
			InventoryOperationEffect.Type.CHANGE_QUANTITY:
				effect.item.num_changed.emit(effect.item.num)
			InventoryOperationEffect.Type.DESTROY_ITEM:
				inventory.occupy_map.item_instance_removed.emit(effect.item, effect.cell_before)
			InventoryOperationEffect.Type.ENTER_INVENTORY:
				inventory.occupy_map.item_instance_added.emit(effect.item)
			InventoryOperationEffect.Type.CHANGE_POSITION:
				inventory.occupy_map.item_instance_position_changed.emit(effect.item, effect.cell_before)
			InventoryOperationEffect.Type.CHANGE_ROTATION:
				effect.item.dir_changed.emit(effect.item.dir)
				inventory.occupy_map.item_instance_rotated.emit(effect.item)
			InventoryOperationEffect.Type.CHANGE_SHAPE:
				effect.item.shape_changed.emit()
				inventory.occupy_map.item_instance_reshaped.emit(effect.item)
	inventory._emit_operation_committed(result_plan)
	_publishing.erase(inventory)
	return InventoryOperationResult.succeeded(result_plan)

static func _save_publication(inventory: InventoryData, items: Array) -> Dictionary:
	var saved := {"objects": {}, "items": {}, "cache": inventory.item_instances.duplicate(), "revision": inventory.revision, "map": {}}
	saved.objects[inventory] = inventory.is_blocking_signals()
	saved.objects[inventory.occupy_map] = inventory.occupy_map.is_blocking_signals()
	for item: ItemInstanceData in items:
		saved.objects[item] = item.is_blocking_signals()
		saved.items[item] = {"num": item.num, "dir": item.dir, "states": item.instance_states}
	for name in ["cells", "region_cells", "occupied_cells", "occupant_to_cells", "occupant_to_center_cell", "placed_item_instances", "unplaced_item_instances"]:
		saved.map[name] = inventory.occupy_map.get(name).duplicate(true)
	return saved

static func _block_publication(saved: Dictionary) -> void:
	for object in saved.objects:
		object.set_block_signals(true)

static func _restore_signal_flags(saved: Dictionary) -> void:
	for object in saved.objects:
		object.set_block_signals(saved.objects[object])

static func _restore_publication(inventory: InventoryData, saved: Dictionary) -> void:
	for item: ItemInstanceData in saved.items:
		item.instance_states = saved.items[item].states
		item.num = saved.items[item].num
		item.dir = saved.items[item].dir
		item._mark_instance_states_ready()
	for name in saved.map:
		inventory.occupy_map.set(name, saved.map[name])
	inventory.item_instances = saved.cache
	inventory.revision = saved.revision

static func _publish_projection(tx: InventoryOperationTransaction) -> bool:
	var inventory := tx.inventory
	var map := inventory.occupy_map
	map.clear_occupancy()
	map.cells = tx._projection.occupy_map.cells.duplicate()
	for actual: ItemInstanceData in tx._actual_to_virtual:
		var projected: ItemInstanceData = tx._actual_to_virtual[actual]
		# 未变化 State 保留原资源身份；变化 State 已在隔离重放中准备完毕。
		if tx._state_changed.has(actual):
			actual.instance_states = tx._prepared_states[actual]
			actual._mark_instance_states_ready()
		if actual.num != projected.num:
			actual.num = projected.num
		if actual.dir != projected.dir:
			actual.dir = projected.dir
	for item in tx.view.get_items():
		if not map.try_register_item_instance_at_placement(item, tx.view.get_cell(item), item.dir):
			return false
	inventory.ensure_occupancy_synced()
	return true

static func _build_transaction_result(tx: InventoryOperationTransaction) -> InventoryOperationPlan:
	var result := InventoryOperationPlan.new()
	result.request = tx.steps[0]
	result.view = tx.rule_plans[0].view
	result.after_view = tx.view
	result.capture_inventory(tx.inventory)
	for actual: ItemInstanceData in tx._actual_to_virtual:
		var before := tx.inventory.has_item_instance(actual)
		var after := tx.view.has_item(actual)
		var projected: ItemInstanceData = tx._actual_to_virtual[actual]
		if not before and not after:
			continue
		var cell := tx.inventory.occupy_map.get_item_center_cell(actual)
		if before and not after:
			var removed := InventoryOperationEffect.create(InventoryOperationEffect.Type.DESTROY_ITEM, actual, tx.inventory)
			removed.cell_before = cell
			removed.quantity_before = actual.num
			removed.quantity_after = 0
			result.effects.append(removed)
		elif not before and after:
			var added := InventoryOperationEffect.create(InventoryOperationEffect.Type.ENTER_INVENTORY, actual, tx.inventory)
			added.cell_after = tx.view.get_cell(actual)
			added.quantity_after = projected.num
			result.effects.append(added)
		else:
			if actual.num != projected.num:
				var quantity := InventoryOperationEffect.create(InventoryOperationEffect.Type.CHANGE_QUANTITY, actual, tx.inventory)
				quantity.quantity_before = actual.num
				quantity.quantity_after = projected.num
				result.effects.append(quantity)
			if cell != tx.view.get_cell(actual):
				var moved := InventoryOperationEffect.create(InventoryOperationEffect.Type.CHANGE_POSITION, actual, tx.inventory)
				moved.cell_before = cell
				moved.cell_after = tx.view.get_cell(actual)
				result.effects.append(moved)
			if actual.dir != projected.dir:
				result.effects.append(InventoryOperationEffect.create(InventoryOperationEffect.Type.CHANGE_ROTATION, actual, tx.inventory))
			if actual.get_local_cells() != projected.get_local_cells():
				result.effects.append(InventoryOperationEffect.create(InventoryOperationEffect.Type.CHANGE_SHAPE, actual, tx.inventory))
	for step in tx.rule_plans:
		for effect in step.effects:
			if effect.type == InventoryOperationEffect.Type.CONSUME_QUANTITY:
				result.effects.append(effect)
	return result
