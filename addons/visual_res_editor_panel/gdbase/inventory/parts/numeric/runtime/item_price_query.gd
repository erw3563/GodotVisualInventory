class_name ItemPriceQuery
extends RefCounted
## 交易扩展按币种键读取固定整数单价；通用数值 Part 不解释币种。
static func find_entry(item_data: ItemData, currency: StringName) -> ItemNumericEntry:
	if item_data == null or str(currency).strip_edges().is_empty():
		return null
	var parts := item_data.get_all_same_type_parts(ItemNumericPart.PART_TYPE)
	if parts.size() != 1:
		return null
	var part := parts[0] as ItemNumericPart
	if part == null or part.validate_configuration() != &"":
		return null
	var entry := part.find_entry(currency)
	if entry == null or entry.storage_mode != ItemNumericEntry.StorageMode.FIXED or entry.number_type != ItemNumericEntry.NumberType.INTEGER:
		return null
	return entry

static func get_base_price(item_data: ItemData, currency: StringName) -> int:
	var entry := find_entry(item_data, currency)
	return maxi(0, int(entry.value)) if entry != null else 0
