class_name InventoryReactionController
extends Node
## InventoryReactionController 监听背包事件，并按物品反应规则执行连锁操作。

const MAX_REACTION_COUNT_PER_BATCH := 128
signal session_reset
signal reaction_finished(item: ItemInstanceData, rule: ItemReactionRule, result: InventoryOperationResult)
signal counter_schedule_rejected(item: ItemInstanceData, counter_key: String, reason_key: StringName)
var operation_context: InventoryOperationContext = InventoryOperationContext.system()
var random := RandomNumberGenerator.new()
var execution_queue: InventoryReactionExecutionQueue
var _execution_ticket: int = 0

func _release_execution_ticket() -> void:
	if execution_queue != null:
		execution_queue.release(_execution_ticket)
	_execution_ticket = 0

func _schedule_pending() -> void:
	_is_processing_pending_reactions = true
	if execution_queue != null:
		_execution_ticket = execution_queue.reserve()
	_process_pending_reactions.call_deferred(_generation)

## 当前绑定并由本节点计算反应的背包数据。
@export var target_inventory_data: InventoryData:
	set(value):
		_release_execution_ticket()
		if target_inventory_data != null:
			_disconnect_inventory_signals(target_inventory_data)
		session_reset.emit()
		_generation += 1
		_pending_reactions.clear()
		_pending_keys.clear()
		_counter_baselines.clear()
		_restore_added.clear()
		_restoring = false
		_is_processing_pending_reactions = false
		target_inventory_data = value
		if target_inventory_data != null:
			_connect_inventory_signals(target_inventory_data)
			_refresh_counter_baselines(false)
## 每条反应规则执行前等待的秒数，0 表示立即执行。
@export_range(0.0, 10.0, 0.1) var reaction_delay_seconds := 0.0

## 等待执行的反应规则队列。
var _generation: int = 0
var _pending_reactions: Array[Dictionary] = []
var _pending_keys: Dictionary = {}
var _turn_event_serial := 0
var _counter_serial := 0
var _counter_baselines: Dictionary = {}
var _restoring := false
var _restore_added: Dictionary = {}
## 防止同一批规则重复安排执行。
var _is_processing_pending_reactions := false

## 包括等待定时器和恢复基线的窗口，供外部稳定边界判断。
func is_idle() -> bool:
	return not _restoring and not _is_processing_pending_reactions and _pending_reactions.is_empty()

## 绑定目标背包，并开始监听其物品变化。
func bind_inventory_data(inventory_data: InventoryData) -> void:
	target_inventory_data = inventory_data

## 解绑当前背包，并停止监听其物品变化。
func unbind_inventory_data() -> void:
	target_inventory_data = null

## 由回合系统调用，触发背包内所有物品的回合结束规则。
func trigger_turn_ended() -> void:
	if target_inventory_data == null:
		return
	_turn_event_serial += 1
	var retries: Array[Dictionary] = []
	for item in target_inventory_data.get_item_instances():
		for rule in _counter_rules(item):
			var part := ItemCounterPart.find(item.item_data, rule.counter_key)
			var state := part.resolve_state(item) if part != null else null
			if rule.retry_on_turn_ended and state != null and state.current_value == 0:
				retries.append({"item": item, "counter_key": rule.counter_key})
	for item_instance_data in target_inventory_data.get_item_instances():
		_enqueue_matching_rules(item_instance_data, ItemReactionRule.TriggerType.TURN_ENDED)
	for retry in retries:
		retry_counter(retry.item, retry.counter_key)

## 连接背包事件。
func _connect_inventory_signals(inventory_data: InventoryData) -> void:
	inventory_data.operation_committed.connect(_on_operation_committed)
	inventory_data.item_removed.connect(_on_counter_item_removed)
	inventory_data.inventory_cleared.connect(_on_inventory_cleared)
	if !inventory_data.item_added.is_connected(_on_inventory_item_added):
		inventory_data.item_added.connect(_on_inventory_item_added)
	if !inventory_data.item_position_changed.is_connected(_on_inventory_item_position_changed):
		inventory_data.item_position_changed.connect(_on_inventory_item_position_changed)

## 断开背包事件。
func _disconnect_inventory_signals(inventory_data: InventoryData) -> void:
	inventory_data.operation_committed.disconnect(_on_operation_committed)
	inventory_data.item_removed.disconnect(_on_counter_item_removed)
	inventory_data.inventory_cleared.disconnect(_on_inventory_cleared)
	if inventory_data.item_added.is_connected(_on_inventory_item_added):
		inventory_data.item_added.disconnect(_on_inventory_item_added)
	if inventory_data.item_position_changed.is_connected(_on_inventory_item_position_changed):
		inventory_data.item_position_changed.disconnect(_on_inventory_item_position_changed)

## 物品放入背包后，安排其放置触发规则。
func _on_inventory_item_added(item_instance_data: ItemInstanceData) -> void:
	_register_counter_baseline(item_instance_data)
	if _restoring:
		_restore_added[item_instance_data] = true
		return
	_enqueue_matching_rules(item_instance_data, ItemReactionRule.TriggerType.ITEM_PLACED)

## 物品移动后，安排其移动触发规则。
func _on_inventory_item_position_changed(
	item_instance_data: ItemInstanceData,
	_previous_cell: Vector2i
) -> void:
	_enqueue_matching_rules(item_instance_data, ItemReactionRule.TriggerType.ITEM_MOVED)

## 将物品上符合当前事件的规则加入待执行队列。
func _enqueue_matching_rules(
	item_instance_data: ItemInstanceData,
	trigger_type: ItemReactionRule.TriggerType
) -> void:
	if target_inventory_data == null or item_instance_data == null:
		return
	if !target_inventory_data.has_item_instance(item_instance_data):
		return
	var item_data := item_instance_data.get_item_data()
	if item_data == null:
		return
	var reaction_parts := item_data.get_all_same_type_parts("Reaction")
	for part_index in reaction_parts.size():
		var reaction_part: ItemPart = reaction_parts[part_index]
		if reaction_part is ItemReactionPart:
			_enqueue_part_rules(item_instance_data, reaction_part, trigger_type, part_index)
	if !_pending_reactions.is_empty() and !_is_processing_pending_reactions:
		_schedule_pending()

## 从一个反应拼图中筛选并加入匹配事件的规则。
func _enqueue_part_rules(
	item_instance_data: ItemInstanceData,
	reaction_part: ItemReactionPart,
	trigger_type: ItemReactionRule.TriggerType,
	part_index: int
) -> void:
	for rule_index in reaction_part.reaction_rules.size():
		var reaction_rule := reaction_part.reaction_rules[rule_index]
		if reaction_rule == null or reaction_rule.trigger_type != trigger_type:
			continue
		var event_id := _turn_event_serial if trigger_type == ItemReactionRule.TriggerType.TURN_ENDED else target_inventory_data.revision
		var key := "%s:%s:%s:%s:%s" % [event_id, item_instance_data.get_instance_id(), trigger_type, part_index, rule_index]
		if _pending_keys.has(key):
			continue
		_pending_keys[key] = true
		_pending_reactions.append({
			"key": key,
			"policy_signature": operation_context.fingerprint(),
			"item_instance_data": item_instance_data,
			"reaction_rule": reaction_rule,
		})

## 按队列顺序执行反应，并限制单批次数以避免无限连锁。
func _process_pending_reactions(generation: int) -> void:
	if generation != _generation:
		return
	while execution_queue != null and not execution_queue.can_execute(_execution_ticket):
		await get_tree().process_frame
		if generation != _generation:
			return
	var processed_reaction_count := 0
	while !_pending_reactions.is_empty():
		if processed_reaction_count >= MAX_REACTION_COUNT_PER_BATCH:
			push_warning("背包反应超过单批执行上限，已停止本批剩余反应。")
			_pending_reactions.clear()
			_pending_keys.clear()
			break
		var pending_reaction: Dictionary = _pending_reactions.pop_front()
		if reaction_delay_seconds > 0.0:
			await get_tree().create_timer(reaction_delay_seconds).timeout
		if generation != _generation:
			return
		_execute_reaction(pending_reaction)
		_pending_keys.erase(pending_reaction.key)
		if generation != _generation:
			return
		processed_reaction_count += 1
	_release_execution_ticket()
	_is_processing_pending_reactions = false
	if !_pending_reactions.is_empty():
		_schedule_pending()

## 委托规则上的反应动作执行一次物品反应。
func _execute_reaction(pending_reaction: Dictionary) -> void:
	if pending_reaction.get("policy_signature", 0) != operation_context.fingerprint():
		return
	if target_inventory_data == null:
		return
	var item_instance_data := pending_reaction.get("item_instance_data") as ItemInstanceData
	var reaction_rule := pending_reaction.get("reaction_rule") as ItemReactionRule
	if item_instance_data == null or reaction_rule == null:
		return
	if !target_inventory_data.has_item_instance(item_instance_data):
		return
	if reaction_rule.action == null:
		return
	if pending_reaction.has("counter_epoch"):
		var entry: Dictionary = _counter_baselines.get(item_instance_data, {}).get(pending_reaction.counter_key, {})
		if entry.get("epoch", -1) != pending_reaction.counter_epoch or entry.get("value", -1) != 0 or not _counter_rules(item_instance_data).has(reaction_rule) or InventoryOperationFingerprint.of([reaction_rule, ItemCounterPart.find(item_instance_data.item_data, pending_reaction.counter_key)]) != pending_reaction.counter_signature:
			reaction_finished.emit(item_instance_data, reaction_rule, InventoryOperationResult.failed(&"stale_counter_event"))
			return
	var result := InventoryReactionProcessor.run_rule(operation_context, reaction_rule, target_inventory_data, item_instance_data, random) if pending_reaction.has("counter_epoch") else InventoryReactionProcessor.run(operation_context, reaction_rule.action, target_inventory_data, item_instance_data, random, reaction_rule.trigger_type)
	reaction_finished.emit(item_instance_data, reaction_rule, result)

## 恢复快照／热换后显式重建；不补发历史零值。
func resync() -> void:
	target_inventory_data = target_inventory_data

func _on_counter_item_removed(item: ItemInstanceData) -> void:
	_counter_baselines.erase(item)

func _on_inventory_cleared() -> void:
	resync()
	_restoring = true
	_finish_restore.call_deferred(_generation)

func _finish_restore(generation: int) -> void:
	if generation == _generation:
		_restoring = false
		_restore_added.clear()

func _on_operation_committed(result: InventoryOperationResult) -> void:
	# 恢复没有 operation_committed；同帧真实入库仍须执行普通放置规则。
	if _restoring and result.plan != null:
		for effect in result.plan.effects:
			if effect.type == InventoryOperationEffect.Type.ENTER_INVENTORY and _restore_added.has(effect.item):
				_restore_added.erase(effect.item)
				_enqueue_matching_rules(effect.item, ItemReactionRule.TriggerType.ITEM_PLACED)
	_refresh_counter_baselines(true)

func _register_counter_baseline(item: ItemInstanceData) -> void:
	if item == null or item.item_data == null or _counter_baselines.has(item):
		return
	var values: Dictionary = {}
	for part in item.item_data.get_all_same_type_parts(ItemCounterPart.get_part_type()):
		if not part is ItemCounterPart:
			continue
		var state: ItemCounterState = part.resolve_state(item)
		if state != null and state.reconcile_with_part(part):
			_counter_serial += 1
			values[part.get_instance_state_key()] = {"value": state.current_value, "epoch": _counter_serial}
	_counter_baselines[item] = values

func _refresh_counter_baselines(emit_zero: bool) -> void:
	if target_inventory_data == null:
		return
	var zeros: Array[Dictionary] = []
	for old_item in _counter_baselines.keys():
		if not target_inventory_data.has_item_instance(old_item):
			_counter_baselines.erase(old_item)
	for item in target_inventory_data.get_item_instances():
		if not _counter_baselines.has(item):
			_register_counter_baseline(item)
			continue
		var old: Dictionary = _counter_baselines[item]
		var next: Dictionary = {}
		for part in item.item_data.get_all_same_type_parts(ItemCounterPart.get_part_type()):
			if not part is ItemCounterPart:
				continue
			var state: ItemCounterState = part.resolve_state(item)
			if state == null or not state.reconcile_with_part(part):
				continue
			var key: String = part.get_instance_state_key()
			var previous: Dictionary = old.get(key, {})
			var epoch: int = previous.get("epoch", -1)
			if previous.is_empty() or previous.value != state.current_value:
				_counter_serial += 1
				epoch = _counter_serial
			next[key] = {"value": state.current_value, "epoch": epoch}
			if emit_zero and previous.get("value", 0) > 0 and state.current_value == 0:
				zeros.append({"item": item, "counter_key": key})
		_counter_baselines[item] = next
	for zero in zeros:
		# 无归零规则的 Counter 是合法独立能力。
		if not _counter_rules(zero.item).is_empty():
			var result := retry_counter(zero.item, zero.counter_key)
			if not result.queued and result.reason_key != &"counter_already_queued" and result.reason_key != &"counter_rule_missing":
				counter_schedule_rejected.emit(zero.item, zero.counter_key, result.reason_key)

func _counter_rules(item: ItemInstanceData) -> Array[ItemReactionRule]:
	var result: Array[ItemReactionRule] = []
	if item == null or item.item_data == null:
		return result
	for part in item.item_data.get_all_same_type_parts(ItemReactionPart.get_part_type()):
		if part is ItemReactionPart:
			for rule in part.reaction_rules:
				if rule != null and rule.trigger_type == ItemReactionRule.TriggerType.COUNTER_ZERO:
					result.append(rule)
	return result

## 返回入队结果；执行结果通过 reaction_finished 观察。
func retry_counter(item: ItemInstanceData, counter_key: String) -> InventoryReactionScheduleResult:
	if target_inventory_data == null or item == null or not target_inventory_data.has_item_instance(item):
		return InventoryReactionScheduleResult.create(false, &"source_item_missing")
	var reason := ItemReactionRule.validate_counter_rules(item.item_data)
	if reason != &"":
		return InventoryReactionScheduleResult.create(false, reason)
	var part := ItemCounterPart.find(item.item_data, counter_key)
	if part == null:
		return InventoryReactionScheduleResult.create(false, &"counter_missing")
	var state := part.resolve_state(item)
	if state == null or not state.reconcile_with_part(part) or state.current_value != 0:
		return InventoryReactionScheduleResult.create(false, &"counter_not_ready")
	_register_counter_baseline(item)
	var entry: Dictionary = _counter_baselines.get(item, {}).get(counter_key, {})
	if entry.get("value", -1) != 0:
		return InventoryReactionScheduleResult.create(false, &"counter_observer_out_of_sync")
	var matched: ItemReactionRule
	for rule in _counter_rules(item):
		if rule.counter_key == counter_key:
			matched = rule
	if matched == null:
		return InventoryReactionScheduleResult.create(false, &"counter_rule_missing")
	var key := "counter:%s:%s:%s" % [item.get_instance_id(), counter_key, entry.epoch]
	if _pending_keys.has(key):
		return InventoryReactionScheduleResult.create(false, &"counter_already_queued")
	_pending_keys[key] = true
	_pending_reactions.append({
		"key": key,
		"policy_signature": operation_context.fingerprint(), "item_instance_data": item, "reaction_rule": matched,
		"counter_key": counter_key, "counter_epoch": entry.epoch,
		"counter_signature": InventoryOperationFingerprint.of([matched, part]),
	})
	if not _is_processing_pending_reactions:
		_schedule_pending()
	return InventoryReactionScheduleResult.create(true)


func _exit_tree() -> void:
	unbind_inventory_data()
