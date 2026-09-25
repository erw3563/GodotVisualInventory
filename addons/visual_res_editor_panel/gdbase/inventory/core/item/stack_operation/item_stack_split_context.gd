class_name ItemStackSplitContext
extends RefCounted
## 单个 State 的只读拆分规划上下文。

var item: ItemInstanceData
var part: ItemPart
var state: ItemInstanceState
var original_num: int = 0
var split_num: int = 0
var remaining_num: int = 0


static func create(
	source_item: ItemInstanceData,
	source_part: ItemPart,
	source_state: ItemInstanceState,
	amount: int
) -> ItemStackSplitContext:
	var context := ItemStackSplitContext.new()
	context.item = source_item
	context.part = source_part
	context.state = source_state
	context.original_num = source_item.num
	context.split_num = amount
	context.remaining_num = source_item.num - amount
	return context
