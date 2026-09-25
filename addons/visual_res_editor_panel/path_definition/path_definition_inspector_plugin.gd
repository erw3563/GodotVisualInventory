@tool
extends EditorInspectorPlugin

const PathDefinitionPropertyEditor := preload(
	"res://addons/visual_res_editor_panel/path_definition/path_definition_property_editor.gd"
)

## 仅处理 PathDefinition 资源，让插件不影响其他资源类型。

func _can_handle(object: Object) -> bool:
	return object is PathDefinition

## 在 paths 属性下方挂载可视化曲线编辑面板，并保留默认数组编辑器。
## 清空按钮会赋回只读默认数组，由 PathDefinition.paths 的归一化 setter 转为可写副本，
## 后续数组编辑与面板编辑都能正常触发变更通知。
func _parse_property(
		object: Object,
		type: int,
		name: String,
		hint_type: int,
		hint_string: String,
		usage_flags: int,
		wide: bool
) -> bool:
	if name != "paths" or type != TYPE_ARRAY:
		return false

	var property_editor: EditorProperty = PathDefinitionPropertyEditor.new()
	property_editor.setup_path_definition(object as PathDefinition)
	add_property_editor(name, property_editor)
	return false
