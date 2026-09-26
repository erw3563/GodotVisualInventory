@tool
extends EditorInspectorPlugin

const ShapeCellsPropertyEditor := preload("res://addons/visual_inventory/shape/shape_cells_property_editor.gd")


## 仅处理 Shape 资源，让插件不会影响其他资源类型。
func _can_handle(object: Object) -> bool:
	return object is Shape


## 在 cells 属性下方挂载自定义可视化面板，并保留默认数组编辑器。
func _parse_property(
	object: Object,
	type: int,
	name: String,
	hint_type: int,
	hint_string: String,
	usage_flags: int,
	wide: bool
) -> bool:
	if name != "cells" or type != TYPE_ARRAY:
		return false

	var shape_cells_property_editor: EditorProperty = ShapeCellsPropertyEditor.new()
	shape_cells_property_editor.setup_shape_resource(object as Shape)
	add_property_editor(name, shape_cells_property_editor)
	return false
