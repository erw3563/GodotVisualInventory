@tool
extends RefCounted

func describe() -> Dictionary:
	return {"type":ItemAnimationPart,"title":"物品动画","fields":{"instance_state_key":"实例状态键","default_appearance_key":"默认外观标识","appearances":"外观列表","animations":"动画列表"}}

func build(form: Control) -> void:
	var fields: Dictionary = describe().fields
	for key in fields:
		form.add_field(key, fields[key])

func diagnose(part: ItemPart) -> String:
	return str(part.call("validate_configuration")) if part.has_method("validate_configuration") else ""
