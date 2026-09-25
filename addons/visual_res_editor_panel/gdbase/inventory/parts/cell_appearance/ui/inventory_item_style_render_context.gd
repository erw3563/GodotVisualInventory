@tool
class_name InventoryItemStyleRenderContext
extends RefCounted
## 一次绘制绑定的网格、默认线宽与视觉父层。
var grid: InventoryGridPanel
var default_border_width := 3.0
var fill_parent: Control
var border_parent: Control

func is_valid() -> bool:
	return is_instance_valid(grid) and is_instance_valid(fill_parent) and is_instance_valid(border_parent) and is_finite(default_border_width) and default_border_width >= 0.0
