@tool
@abstract
class_name InventoryItemStyleRenderer
extends Node
## 每个图形独占的渲染实例，拥有绘制节点与格集合快照。
var style: InventoryItemVisualStyle
var context: InventoryItemStyleRenderContext
var border_cells: Array[Vector2i] = []
var fill_cells: Array[Vector2i] = []
var drawing_nodes: Array[Control] = []

func configure(value: InventoryItemVisualStyle, binding: InventoryItemStyleRenderContext) -> bool:
	release()
	if value == null or binding == null or not binding.is_valid() or not value.validate_configuration().is_empty() or not _accept_style(value):
		return false
	style = value
	context = binding
	return true

@abstract func _accept_style(value: InventoryItemVisualStyle) -> bool
@abstract func _render() -> void

func render(borders: Array[Vector2i], fills: Array[Vector2i]) -> void:
	clear()
	if style == null or context == null or not context.is_valid() or not style.validate_configuration().is_empty():
		return
	if style.use_border:
		border_cells = borders.duplicate()
	if style.use_fill:
		fill_cells = fills.duplicate()
	_render()

func own_drawing(control: Control, parent: Control) -> void:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(control)
	drawing_nodes.append(control)

func clear() -> void:
	for control in drawing_nodes:
		if is_instance_valid(control):
			if control.get_parent() != null:
				control.get_parent().remove_child(control)
			control.queue_free()
	drawing_nodes.clear()
	border_cells.clear()
	fill_cells.clear()

func release() -> void:
	clear()
	style = null
	context = null

func _exit_tree() -> void:
	release()
