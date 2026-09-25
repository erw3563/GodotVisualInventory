@tool
class_name InventoryItemTags
extends RefCounted
## 库存标签的稳定键；物品只存数据，具体 Consumer 解释行为。
const NO_TAKE := "inventory.no_take"
const NO_PLACE := "inventory.no_place"
const NO_CONSUME := "inventory.no_consume"
const INFINITE_SUPPLY := "inventory.infinite_supply"
const DISPLAY_NAMES := {
	NO_TAKE: "禁止拿取", NO_PLACE: "禁止放入",
	NO_CONSUME: "禁止消耗", INFINITE_SUPPLY: "无限供应",
}

static func has_tag(item: ItemInstanceData, tag: String) -> bool:
	if item == null or item.item_data == null:
		return false
	var part := item.item_data.get_type_part(ItemTagPart.get_part_type()) as ItemTagPart
	return part != null and part.has_tag(tag)
