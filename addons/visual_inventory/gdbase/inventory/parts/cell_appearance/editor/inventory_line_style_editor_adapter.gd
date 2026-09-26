@tool
extends RefCounted
## 线条样式的专有字段。
static func build(form: Control) -> void:
	form.build_line_width()
