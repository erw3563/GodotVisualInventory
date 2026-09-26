@tool
extends RefCounted

func describe() -> Dictionary:
	return {"type":ItemCounterPart,"title":"计数器","fields":{"instance_state_key":"实例状态键","initial_value":"初始计数"}}

func build(form: Control) -> void:
	var fields: Dictionary = describe().fields
	for key in fields:
		form.add_field(key, fields[key])

func diagnose(part: ItemPart) -> String:
	return str(part.call("validate_configuration")) if part.has_method("validate_configuration") else ""
