@tool
extends EditorInspectorPlugin

const InventoryDataPropertyEditor := preload(
	"res://addons/visual_res_editor_panel/inventory_data/inventory_data_property_editor.gd"
)


## 处理 InventoryData 资源类型。
func _can_handle(object: Object) -> bool:
	return object is InventoryData


## 在检查器顶部挂载背包可视化编辑器。
func _parse_begin(object: Object) -> void:
	var inventory_data_property_editor: InventoryDataPropertyEditor = InventoryDataPropertyEditor.new()
	inventory_data_property_editor.setup_inventory_data_resource(object as InventoryData)
	add_custom_control(inventory_data_property_editor)
