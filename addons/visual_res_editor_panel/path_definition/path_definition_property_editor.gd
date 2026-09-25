@tool
extends EditorProperty

const PathDefinitionEditorPanel := preload(
	"res://addons/visual_res_editor_panel/path_definition/path_definition_panel.gd"
)

var definition: PathDefinition
var panel: VBoxContainer

func _init() -> void:
	panel = PathDefinitionEditorPanel.new()
	add_child(panel)
	set_bottom_editor(panel)
	panel.paths_changed.connect(_on_panel_paths_changed)

## 绑定当前正在检查器中编辑的 PathDefinition 资源。
func setup_path_definition(new_definition: PathDefinition) -> void:
	definition = new_definition
	panel.setup_path_definition(definition)

## 当检查器属性刷新时（外部修改或撤销重做）重新同步面板。
func _update_property() -> void:
	var edited_definition := get_edited_object() as PathDefinition
	if edited_definition != null:
		definition = edited_definition
	if definition != null:
		panel.setup_path_definition(definition)

## 接收可视化面板提交的路径列表修改并写回资源属性。
func _on_panel_paths_changed(new_paths: Array[Curve2D]) -> void:
	emit_changed(get_edited_property(), new_paths)
