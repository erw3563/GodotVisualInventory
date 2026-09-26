@tool
@abstract
class_name InventoryItemVisualStyle
extends Resource
## 共享静态样式协议，具体类型创建独立渲染实例。
@export var use_border := true
@export var border_color := Color(1.0, 0.68, 0.2, 1.0)
@export var use_fill := true
@export var fill_color := Color(1.0, 0.68, 0.2, 0.15)

func validate_configuration() -> StringName:
	for color in [border_color, fill_color]:
		for component in [color.r, color.g, color.b, color.a]:
			if not is_finite(component):
				return &"appearance_style_color_invalid"
	return _validate_style()

@abstract func _validate_style() -> StringName
@abstract func create_renderer() -> InventoryItemStyleRenderer

func derive_zone_style() -> InventoryItemVisualStyle:
	var result := duplicate(true) as InventoryItemVisualStyle
	result.use_border = false
	result.use_fill = true
	result.fill_color.a *= 0.6
	return result
