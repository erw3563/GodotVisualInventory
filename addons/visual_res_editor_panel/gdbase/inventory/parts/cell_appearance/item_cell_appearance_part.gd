@tool
class_name ItemCellAppearancePart
extends ItemPart
## 物品占格的命名外观；状态和业务触发由外部调用方决定。
@export var appearances: Array[InventoryCellAppearanceEntry] = []

static func get_part_type() -> String:
	return "CellAppearance"

func allows_multiple() -> bool:
	return false

func validate_appearances() -> StringName:
	var seen: Dictionary = {}
	for entry in appearances:
		if entry == null:
			return &"appearance_entry_missing"
		if entry.id == &"":
			return &"appearance_id_empty"
		if entry.style == null:
			return &"appearance_style_missing"
		if seen.has(entry.id):
			return &"appearance_id_duplicate"
		var reason := entry.style.validate_configuration()
		if not reason.is_empty():
			return reason
		seen[entry.id] = true
	return &""

func validate_configuration() -> StringName:
	return validate_appearances()

func resolve_style(id: StringName) -> InventoryItemVisualStyle:
	if not validate_appearances().is_empty():
		return null
	for entry in appearances:
		if entry.id == id:
			return entry.style
	return null
