class_name InventoryCellMark
extends RefCounted
## 物品外部框：一组格子与一个视觉样式的纯数据组合。
## 由物品数据层（边框拼图）产出，覆盖层按通用规则渲染，不含物品与修饰语义。

## 标记覆盖的格子集合。
var cells: Array[Vector2i] = []
## 标记使用的视觉样式。
var style: InventoryItemVisualStyle


## 初始化标记内容。
func init_mark(mark_cells: Array[Vector2i], mark_style: InventoryItemVisualStyle) -> void:
	cells = mark_cells
	style = mark_style


## 标记是否不携带任何格子或样式。
func is_empty() -> bool:
	return cells.is_empty() or style == null
