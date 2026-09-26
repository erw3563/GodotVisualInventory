@tool
extends EditorInspectorPlugin

const OccupyMapCellsPropertyEditor := preload(
	"res://addons/visual_inventory/occupy/occupy_map_cells_property_editor.gd"
)


## 处理 OccupyMap 及其子类，让插件不会影响其他资源类型。
func _can_handle(object: Object) -> bool:
	return object is OccupyMap


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

	var occupy_map_cells_property_editor: EditorProperty = OccupyMapCellsPropertyEditor.new()
	occupy_map_cells_property_editor.setup_occupy_map_resource(object as OccupyMap)
	add_property_editor(name, occupy_map_cells_property_editor)
	return false
