@tool
@abstract
class_name ItemReactionAction
extends Resource
## ItemReactionAction 是背包反应动作的抽象基类。

## 纯规划。执行器统一提交，具体动作不得直接写入真实库存。
@abstract func plan(context: ItemReactionPlanContext) -> ItemReactionPlanResult

func validate_configuration() -> StringName:
	return &""

func get_child_actions() -> Array[ItemReactionAction]:
	return []
