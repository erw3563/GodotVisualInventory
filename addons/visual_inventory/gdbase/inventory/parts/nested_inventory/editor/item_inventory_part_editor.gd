@tool
extends RefCounted

func describe() -> Dictionary:
	return {"type":ItemInventoryPart,"title":"内嵌库存","fields":{"instance_state_key":"实例状态键","inventory_template":"库存模板","nested_panel_definition":"嵌套面板布局"}}

func build(form: Control) -> void:
	var fields: Dictionary = describe().fields
	for key in fields:
		form.add_field(key, fields[key])

func diagnose(part: ItemPart) -> String:
	return str(part.call("validate_configuration")) if part.has_method("validate_configuration") else ""
