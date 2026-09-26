@tool
class_name InventoryTargetTagFilter
extends InventoryTargetFilter
## 通过标签 Part 匹配候选物品的静态特征。

@export var tag: StringName

func validate_configuration() -> StringName:
	return &"missing_item_tag" if tag == &"" else &""

func matches(item: ItemInstanceData, context: InventoryTargetQueryContext) -> bool:
	var fact := context.get_item(item)
	if fact == null or fact.item_data == null:
		return false
	var part := fact.item_data.get_type_part(ItemTagPart.get_part_type()) as ItemTagPart
	return part != null and part.has_tag(tag)
