@tool
class_name InventoryPanelBackground
extends PanelContainer
## 布局纯显示背景：以 StyleBox 绘制面板样式，可选 Material（含 ShaderMaterial）；不参与指针命中。


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## 写入 StyleBox 与材质；空 StyleBox 不绘制面板样式；材质赋给本节点。
func configure(style: StyleBox, surface_material: Material) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if style != null:
		add_theme_stylebox_override("panel", style)
	else:
		remove_theme_stylebox_override("panel")
	material = surface_material
