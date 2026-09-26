@tool
class_name InventoryAppearanceKeyEntry
extends Resource
## 外观键的编辑名称与用途。
@export var id: StringName
@export var display_name := ""
@export var description := ""

func same_metadata(other: Resource) -> bool:
	return other != null and id == other.id and display_name == other.display_name and description == other.description
