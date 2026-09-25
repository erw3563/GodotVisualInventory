@tool
class_name ItemReactionPart
extends ItemPart
## ItemReactionPart 为物品声明可响应背包事件的反应规则。

## 此物品拥有的反应规则。
@export var reaction_rules: Array[ItemReactionRule] = []

## 返回拼图类型，用于从 ItemData 中查询反应能力。
static func get_part_type() -> String:
	return "Reaction"
