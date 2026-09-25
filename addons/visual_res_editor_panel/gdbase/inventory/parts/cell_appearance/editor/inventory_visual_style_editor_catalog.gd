@tool
extends RefCounted
## 编辑器可创建的具体样式与专有表单。
const TYPES := [
	{"title": "线条", "script": preload("res://addons/visual_res_editor_panel/gdbase/inventory/parts/cell_appearance/inventory_item_line_visual_style.gd"), "editor": preload("res://addons/visual_res_editor_panel/gdbase/inventory/parts/cell_appearance/editor/inventory_line_style_editor_adapter.gd")},
	{"title": "贴图", "script": preload("res://addons/visual_res_editor_panel/gdbase/inventory/parts/cell_appearance/inventory_item_texture_visual_style.gd"), "editor": preload("res://addons/visual_res_editor_panel/gdbase/inventory/parts/cell_appearance/editor/inventory_texture_style_editor_adapter.gd")}
]
static func index_of(style: InventoryItemVisualStyle) -> int:
	for index in TYPES.size():
		if style != null and style.get_script() == TYPES[index].script:
			return index
	return -1

static func describe_error(reason: StringName) -> String:
	return {
		&"appearance_style_color_invalid": "颜色必须是有限数值。",
		&"appearance_style_width_invalid": "线宽必须是有限数值。",
		&"appearance_frame_texture_missing": "请选择框贴图。",
		&"appearance_frame_margins_invalid": "框贴图与边距无效：四边距需为正，且合计小于源图尺寸。",
		&"appearance_fill_texture_invalid": "填充贴图尺寸或边距无效。"
	}.get(reason, str(reason))
