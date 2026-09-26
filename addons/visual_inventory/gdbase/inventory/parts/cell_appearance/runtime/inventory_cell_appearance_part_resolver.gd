class_name InventoryCellAppearancePartResolver
extends RefCounted

static func get_first_part(item: ItemInstanceData) -> ItemCellAppearancePart:
	if item == null or item.item_data == null:
		return null
	return item.item_data.get_type_part(ItemCellAppearancePart.get_part_type()) as ItemCellAppearancePart

static func resolve_style(item: ItemInstanceData, id: StringName, fallback: ItemCellAppearancePart = null) -> InventoryItemVisualStyle:
	var part := get_first_part(item)
	if part != null:
		if not part.validate_appearances().is_empty():
			return null
		var style := part.resolve_style(id)
		if style != null:
			return style
	return fallback.resolve_style(id) if fallback != null else null
