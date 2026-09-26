@tool
extends RefCounted

func describe() -> Dictionary:
	return {"type":ItemShapePart,"title":"形状","fields":{"instance_state_key":"实例状态键","shape":"轮廓","stack_merge_mode":"堆叠合并方式"}}

func build(form: Control) -> void:
	var fields: Dictionary = describe().fields
	for key in fields:
		form.add_field(key, fields[key])

func diagnose(part: ItemPart) -> String:
	return str(part.call("validate_configuration")) if part.has_method("validate_configuration") else ""
