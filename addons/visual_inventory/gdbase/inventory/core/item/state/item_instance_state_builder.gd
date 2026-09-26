@tool
class_name ItemInstanceStateBuilder
extends RefCounted
## 从 ItemData 模板构建本件实例状态。

## 遍历动态 Part 并生成状态；空键或冲突键会使整次构建失败。
static func build(item_data: ItemData, stack_num: int = 1) -> Array[ItemInstanceState]:
	var rebuilt_states: Array[ItemInstanceState] = []
	if item_data == null:
		return rebuilt_states
	var part_index: Dictionary = {}
	if !try_build_part_state_index(item_data, part_index):
		return rebuilt_states
	for state_key: String in part_index:
		var entry: Dictionary = part_index[state_key]
		if not entry.required:
			continue
		var created_state := (entry.prototype as ItemInstanceState).prepare_initial_stack_state(
			stack_num
		)
		if !_is_prepared_state_valid(created_state, state_key, entry.state_script as Script):
			return []
		rebuilt_states.append(created_state)
	return rebuilt_states


## 校验动态 Part 的稳定键契约；测试可关闭错误输出，仅检查判定。
static func validate_part_state_schema(item_data: ItemData, report_errors: bool = true) -> bool:
	var part_index: Dictionary = {}
	return try_build_part_state_index(item_data, part_index, report_errors)

## 只读校验已有状态的键、类型、实例事实与必需键齐全，不补建、不删改。
static func validate_existing_states(states: Array[ItemInstanceState], item_data: ItemData) -> bool:
	var schema: Dictionary = {}
	if not try_build_part_state_index(item_data, schema, false):
		return false
	var seen: Dictionary = {}
	for state in states:
		if state == null or seen.has(state.state_key) or not schema.has(state.state_key):
			return false
		if state.get_script() != schema[state.state_key].state_script or not state.is_valid_instance_state():
			return false
		seen[state.state_key] = true
	for state_key: String in schema:
		if schema[state_key].required and not seen.has(state_key):
			return false
	return true


## 原子建立 state_key -> {part, state_script, prototype, required} 索引。
## 内建可选项允许 part/prototype 为空；索引不创建其状态。
static func try_build_part_state_index(
	item_data: ItemData,
	part_index: Dictionary,
	report_errors: bool = true
) -> bool:
	part_index.clear()
	if item_data == null:
		if report_errors:
			push_error("ItemInstanceStateBuilder: ItemData 不能为空")
		return false
	part_index.merge(ItemInstanceData.get_builtin_state_schema())
	for item_part in item_data.parts:
		if item_part == null:
			continue
		var prototype := item_part.create_instance_state()
		if prototype == null:
			continue
		var state_key := prototype.state_key
		if state_key.is_empty():
			if report_errors:
				push_error("ItemInstanceStateBuilder: 动态 Part %s 的 state_key 不能为空" % [
					item_data._get_part_type(item_part),
				])
			part_index.clear()
			return false
		if part_index.has(state_key):
			if report_errors:
				push_error("ItemInstanceStateBuilder: 动态 Part 的 state_key 冲突：%s" % state_key)
			part_index.clear()
			return false
		part_index[state_key] = {
			"part": item_part,
			"state_script": prototype.get_script(),
			"prototype": prototype,
			"required": true,
		}
	return true


static func _is_prepared_state_valid(
	state: ItemInstanceState, state_key: String, expected_script: Script
) -> bool:
	if state == null:
		push_error("ItemInstanceStateBuilder: State %s 的初始化结果不能为空" % state_key)
		return false
	if state.state_key != state_key:
		push_error("ItemInstanceStateBuilder: State 初始化改变了稳定键 %s" % state_key)
		return false
	if state.get_script() != expected_script:
		push_error("ItemInstanceStateBuilder: State %s 的初始化结果类型不匹配" % state_key)
		return false
	return true

## 补缺并把已有 State 与当前 Part 按稳定键对账；模板已删除的 State 同批清除。
static func reconcile_states(
	states: Array[ItemInstanceState], item_data: ItemData, stack_num: int = 1
) -> bool:
	if item_data == null:
		return true
	var part_index: Dictionary = {}
	if !try_build_part_state_index(item_data, part_index):
		return false
	var state_by_key: Dictionary = {}
	for state in states:
		if state == null:
			push_error("ItemInstanceStateBuilder: 实例 State 不能为空")
			return false
		if state.state_key.is_empty():
			push_error("ItemInstanceStateBuilder: 实例 State 的 state_key 不能为空")
			return false
		if state_by_key.has(state.state_key):
			push_error("ItemInstanceStateBuilder: 实例 State 键重复：%s" % state.state_key)
			return false
		state_by_key[state.state_key] = state
	for state_key: String in part_index:
		var entry: Dictionary = part_index[state_key]
		var state := state_by_key.get(state_key) as ItemInstanceState
		if state == null:
			if not entry.required:
				continue
			state = (entry.prototype as ItemInstanceState).prepare_initial_stack_state(stack_num)
			if !_is_prepared_state_valid(state, state_key, entry.state_script as Script):
				return false
			state_by_key[state_key] = state
		var expected_script := entry.state_script as Script
		if state.get_script() != expected_script:
			push_error("ItemInstanceStateBuilder: State 键 %s 类型不匹配，实际=%s 期望=%s" % [
				state_key,
				state.get_script(),
				expected_script,
			])
			return false
		if not state.is_valid_instance_state():
			push_error("ItemInstanceStateBuilder: State %s 的实例事实非法" % state_key)
			return false
		if !state.reconcile_with_part(entry.part as ItemPart):
			return false
	var reconciled_states: Array[ItemInstanceState] = []
	for state_key: String in part_index:
		if state_by_key.has(state_key):
			reconciled_states.append(state_by_key[state_key] as ItemInstanceState)
	states.assign(reconciled_states)
	return true
