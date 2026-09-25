@tool
class_name ItemReactionRule
extends Resource
## ItemReactionRule 定义物品在特定事件下执行的一条反应规则。

## 可触发反应规则的背包事件类型。
enum TriggerType {
	ITEM_PLACED,
	ITEM_MOVED,
	TURN_ENDED,
	COUNTER_ZERO,
}

## 触发这条规则的事件类型。
@export var trigger_type: TriggerType = TriggerType.ITEM_PLACED:
	set(value):
		trigger_type = value
		notify_property_list_changed()
## 触发后要执行的反应动作。
@export var action: ItemReactionAction
## 成功后由 Presenter 消费；空值不播放，不参与业务合法性校验。
@export var success_animation_key: StringName

## 仅 COUNTER_ZERO 使用：物品上唯一的 Counter State 稳定键。
@export var counter_key: String = ""
## 仅 COUNTER_ZERO 使用；回合入口显式重试调用开始时已就绪的计数器。
@export var retry_on_turn_ended := false

func _validate_property(property: Dictionary) -> void:
	if property.name in ["counter_key", "retry_on_turn_ended"] and trigger_type != TriggerType.COUNTER_ZERO:
		property.usage &= ~PROPERTY_USAGE_EDITOR

func validate_configuration(item: ItemData) -> StringName:
	if trigger_type not in TriggerType.values():
		return &"invalid_reaction_trigger"
	if trigger_type == TriggerType.COUNTER_ZERO:
		var reason := ItemCounterPart.validate_item(item)
		if reason != &"":
			return reason
		if ItemCounterPart.find(item, counter_key) == null:
			return &"counter_missing"
	return InventoryReactionProcessor.validate_tree(action)

## 跨全部 Reaction Part 校验唯一归零规则，不依赖数组位置。
static func validate_counter_rules(item: ItemData) -> StringName:
	var reason := ItemCounterPart.validate_item(item)
	if reason != &"":
		return reason
	var keys: Dictionary = {}
	for part in item.get_all_same_type_parts(ItemReactionPart.get_part_type()):
		if not part is ItemReactionPart:
			continue
		for rule in part.reaction_rules:
			if rule == null or rule.trigger_type != TriggerType.COUNTER_ZERO:
				continue
			reason = rule.validate_configuration(item)
			if reason != &"":
				return reason
			if keys.has(rule.counter_key):
				return &"duplicate_counter_zero_rule"
			keys[rule.counter_key] = true
	return &""
