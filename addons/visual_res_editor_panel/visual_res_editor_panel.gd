@tool
extends EditorPlugin

const ShapeCellsInspectorPlugin := preload("res://addons/visual_res_editor_panel/shape/shape_cells_inspector_plugin.gd")
const OccupyMapCellsInspectorPlugin := preload(
	"res://addons/visual_res_editor_panel/occupy/occupy_map_cells_inspector_plugin.gd"
)
const InventoryDataInspectorPlugin := preload(
	"res://addons/visual_res_editor_panel/inventory_data/inventory_data_inspector_plugin.gd"
)
const HostDefinitionInspectorPlugin = preload("res://addons/visual_res_editor_panel/inventory_host_definition/inventory_host_definition_inspector_plugin.gd")
const ItemDataInspectorPlugin = preload("res://addons/visual_res_editor_panel/item_data/item_data_inspector_plugin.gd")

var shape_cells_inspector_plugin: EditorInspectorPlugin
var occupy_map_cells_inspector_plugin: EditorInspectorPlugin
var inventory_data_inspector_plugin: EditorInspectorPlugin
var host_definition_inspector: EditorInspectorPlugin
var item_data_inspector: EditorInspectorPlugin


## 可视化资源编辑面板：注册库存相关检查器扩展。
func _enter_tree() -> void:
	ensure_host_definition_inspector()
	ensure_item_data_inspector()
	shape_cells_inspector_plugin = ShapeCellsInspectorPlugin.new()
	add_inspector_plugin(shape_cells_inspector_plugin)

	occupy_map_cells_inspector_plugin = OccupyMapCellsInspectorPlugin.new()
	add_inspector_plugin(occupy_map_cells_inspector_plugin)

	inventory_data_inspector_plugin = InventoryDataInspectorPlugin.new()
	add_inspector_plugin(inventory_data_inspector_plugin)


## 支持开发期脚本热重载后补注册，已有会话不重复创建。
func ensure_host_definition_inspector() -> void:
	if host_definition_inspector == null:
		host_definition_inspector = HostDefinitionInspectorPlugin.new()
		host_definition_inspector.undo_manager = get_undo_redo()
		add_inspector_plugin(host_definition_inspector)


func _create_new_item() -> void:
	ensure_item_data_inspector()
	item_data_inspector.open_editor(ItemData.new())


func ensure_item_data_inspector() -> void:
	if item_data_inspector == null:
		item_data_inspector = ItemDataInspectorPlugin.new()
		item_data_inspector.undo_manager = get_undo_redo()
		add_inspector_plugin(item_data_inspector)
		add_tool_menu_item("新建物品", _create_new_item)


## 移除插件注册的检查器扩展。
func _exit_tree() -> void:
	remove_tool_menu_item("新建物品")
	if item_data_inspector != null:
		item_data_inspector.clear_sessions()
		remove_inspector_plugin(item_data_inspector)
		item_data_inspector = null
	if host_definition_inspector != null:
		host_definition_inspector.clear_sessions()
		remove_inspector_plugin(host_definition_inspector)
		host_definition_inspector = null
	if shape_cells_inspector_plugin != null:
		remove_inspector_plugin(shape_cells_inspector_plugin)
		shape_cells_inspector_plugin = null

	if occupy_map_cells_inspector_plugin != null:
		remove_inspector_plugin(occupy_map_cells_inspector_plugin)
		occupy_map_cells_inspector_plugin = null

	if inventory_data_inspector_plugin != null:
		remove_inspector_plugin(inventory_data_inspector_plugin)
		inventory_data_inspector_plugin = null


func _build() -> bool:
	return true
