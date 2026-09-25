class_name ItemStackOperationCommitter
extends RefCounted
## 只应用已经完整规划出的确定 State 与数量结果。


static func commit_merge(plan: ItemStackOperationPlan) -> bool:
	if plan == null or !plan.allowed or plan.type != ItemStackOperationPlan.Type.MERGE:
		return false
	if !plan.matches_current_facts():
		return false
	var fresh := ItemStackOperationPlanner.plan_merge(
		plan.target_item, plan.source_item, plan.transfer_num
	)
	if !fresh.allowed:
		return false
	return apply_prepared_merge(fresh)


static func apply_prepared_merge(plan: ItemStackOperationPlan) -> bool:
	if plan == null or !plan.allowed or plan.type != ItemStackOperationPlan.Type.MERGE:
		return false
	if plan.target_item == null or plan.source_item == null:
		return false
	if plan.target_item.num != plan.target_num_before \
			or plan.source_item.num != plan.source_num_before:
		return false
	plan.target_item.instance_states = plan.target_states
	plan.target_item.num = plan.target_num_after
	plan.source_item.instance_states = plan.source_states
	plan.source_item.num = plan.source_num_after
	return true


static func commit_split(plan: ItemStackOperationPlan) -> ItemInstanceData:
	if plan == null or !plan.allowed or plan.type != ItemStackOperationPlan.Type.SPLIT:
		return null
	if !plan.matches_current_facts():
		return null
	var fresh := ItemStackOperationPlanner.plan_split(plan.target_item, plan.transfer_num)
	if !fresh.allowed:
		return null
	return apply_prepared_split(fresh)


static func apply_prepared_split(plan: ItemStackOperationPlan) -> ItemInstanceData:
	if plan == null or !plan.allowed or plan.type != ItemStackOperationPlan.Type.SPLIT:
		return null
	if plan.target_item == null or plan.target_item.num != plan.target_num_before:
		return null
	var split_item := ItemInstanceData.new()
	split_item.item_data = plan.target_item.item_data
	split_item.dir = plan.target_item.dir
	split_item.instance_states = plan.source_states
	split_item.num = plan.source_num_after
	split_item._mark_instance_states_ready()
	plan.target_item.instance_states = plan.target_states
	plan.target_item.num = plan.target_num_after
	plan.target_item._mark_instance_states_ready()
	return split_item


## 将已准备好的拆分结果应用到 Planner 持有的未归属实例，保持 Plan/Effect 中的实例身份稳定。
static func apply_prepared_split_into(
	plan: ItemStackOperationPlan, split_item: ItemInstanceData
) -> bool:
	if plan == null or !plan.allowed or plan.type != ItemStackOperationPlan.Type.SPLIT:
		return false
	if plan.target_item == null or split_item == null \
			or plan.target_item == split_item \
			or plan.target_item.num != plan.target_num_before:
		return false
	split_item.item_data = plan.target_item.item_data
	split_item.dir = plan.target_item.dir
	split_item.instance_states = plan.source_states
	split_item.num = plan.source_num_after
	split_item._mark_instance_states_ready()
	plan.target_item.instance_states = plan.target_states
	plan.target_item.num = plan.target_num_after
	plan.target_item._mark_instance_states_ready()
	return true
