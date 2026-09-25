@tool
class_name InventoryItemLineVisualStyle
extends InventoryItemVisualStyle
## 线条边框与纯色占格填充。
@export var border_width := -1.0

func _validate_style() -> StringName:
	return &"" if is_finite(border_width) else &"appearance_style_width_invalid"

func create_renderer() -> InventoryItemStyleRenderer:
	return InventoryItemLineStyleRenderer.new()
