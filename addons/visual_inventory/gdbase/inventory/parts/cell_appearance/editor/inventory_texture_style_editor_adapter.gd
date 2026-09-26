@tool
extends RefCounted
## 贴图样式的专有字段。
static func build(form: Control) -> void:
	form.build_texture("frame_texture", "框贴图")
	form.build_texture("fill_texture", "填充贴图")
	form.build_margins()
