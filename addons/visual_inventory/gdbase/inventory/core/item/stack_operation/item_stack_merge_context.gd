class_name ItemStackMergeContext
extends RefCounted
## 单个 Part / State 的只读合并规划上下文。

var target_item: ItemInstanceData
var source_item: ItemInstanceData
var target_part: ItemPart
var source_part: ItemPart
var target_state: ItemInstanceState
var source_state: ItemInstanceState
var target_num: int = 0
var source_num: int = 0
var transfer_num: int = 0


static func create(
	target: ItemInstanceData,
	source: ItemInstanceData,
	to_part: ItemPart,
	from_part: ItemPart,
	to_state: ItemInstanceState,
	from_state: ItemInstanceState,
	amount: int
) -> ItemStackMergeContext:
	var context := ItemStackMergeContext.new()
	context.target_item = target
	context.source_item = source
	context.target_part = to_part
	context.source_part = from_part
	context.target_state = to_state
	context.source_state = from_state
	context.target_num = target.num
	context.source_num = source.num
	context.transfer_num = amount
	return context
