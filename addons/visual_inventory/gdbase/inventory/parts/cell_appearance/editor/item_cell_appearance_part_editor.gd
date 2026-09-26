@tool
extends RefCounted
const AppearanceEditor = preload("res://addons/visual_inventory/gdbase/inventory/parts/cell_appearance/editor/inventory_cell_appearance_editor.gd")

func describe() -> Dictionary:
	return {"type":ItemCellAppearancePart,"title":"物品框","fields":{"instance_state_key":"实例状态键","appearances":"外观列表"}}

func build(form: Control) -> void:
	form.declared_fields.append("appearances")
	var editor := AppearanceEditor.new()
	editor.setup(form, false)
	form.add_child(editor)
	form.controls["appearances"] = editor
	var toggle := Button.new()
	toggle.text = "高级字段"
	toggle.toggle_mode = true
	form.add_child(toggle)
	form.add_field("instance_state_key", "实例状态键")
	var advanced: Control = form.get_child(-1)
	if advanced != toggle:
		advanced.hide()
		toggle.toggled.connect(func(expanded: bool): advanced.visible = expanded)

func diagnose(part: ItemPart) -> String:
	return str(part.call("validate_configuration")) if part.has_method("validate_configuration") else ""
