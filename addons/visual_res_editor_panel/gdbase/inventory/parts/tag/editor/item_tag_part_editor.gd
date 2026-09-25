@tool
extends RefCounted

func describe() -> Dictionary:
	return {"type":ItemTagPart,"title":"标签","fields":{"instance_state_key":"实例状态键","tags":"标签"}}

func build(form: Control) -> void:
	form.add_note("标签描述物品特性，由处理器解释；禁止拿取等约束按当前 Host 的配置生效。")
	form.add_note("无限供应：普通拿取生成全新物品，保留来源；产物也保留此标签。无限面板不要求此标签。")
	form.add_field("instance_state_key", "实例状态键")
	form.add_string_choices("tags", "标签", form.get_field_choices("tags"))

func diagnose(part: ItemPart) -> String:
	return str(part.call("validate_configuration")) if part.has_method("validate_configuration") else ""
