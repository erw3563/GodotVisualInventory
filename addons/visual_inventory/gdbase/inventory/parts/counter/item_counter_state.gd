@tool
class_name ItemCounterState
extends ItemInstanceState
## 只保存当前值；计数不按堆叠数量派生。
@export var current_value: int = 0

func reconcile_with_part(part: ItemPart) -> bool:
	return part is ItemCounterPart and part.validate_configuration() == &"" and part.get_instance_state_key() == state_key and current_value >= 0

func plan_stack_merge(_context: ItemStackMergeContext) -> ItemStateMergePlan:
	return ItemStateMergePlan.reject(&"counter_stack_merge_disabled")

func plan_stack_split(_context: ItemStackSplitContext) -> ItemStateSplitPlan:
	return ItemStateSplitPlan.reject(&"counter_stack_split_disabled")

func get_description_panel() -> Array[Control]:
	var label := Label.new()
	label.text = "%s：%d%s" % [state_key, current_value, "（就绪）" if current_value == 0 else ""]
	return [label]
