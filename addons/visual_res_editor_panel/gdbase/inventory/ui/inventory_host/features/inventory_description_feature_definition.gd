@tool
class_name InventoryDescriptionFeatureDefinition
extends InventoryHostFeatureDefinition
## 描述功能独占悬停与主动查看入口，并创建面板或显式借用现有面板。
## 现有面板路径相对 Host；也可由组装根按本功能类型注入 Presenter。
enum PanelSource { SCENE, EXISTING }
@export_storage var panel_source: int = PanelSource.SCENE
@export var panel_scene: PackedScene = load("res://addons/visual_res_editor_panel/gdbase/inventory/ui/description/item_description_popup.tscn")
@export_storage var existing_panel_path: NodePath
@export var hover_enabled := true
@export_range(0.0, 10.0, 0.05) var hover_delay := 1.0
@export var active_enabled := true

func validate_configuration(_features: Array[InventoryHostFeatureDefinition]) -> StringName:
	if panel_source == PanelSource.SCENE:
		if panel_scene == null:
			return &"inventory_description_panel_missing"
		if not existing_panel_path.is_empty():
			return &"inventory_description_source_conflict"
	elif panel_source == PanelSource.EXISTING:
		if panel_scene != null:
			return &"inventory_description_source_conflict"
	else:
		return &"inventory_description_source_invalid"
	if not is_finite(hover_delay) or hover_delay < 0.0:
		return &"inventory_description_delay_invalid"
	return &""

func create_assembly(context: InventoryHostFeatureContext) -> InventoryHostFeatureAssembly:
	if context == null or not validate_configuration([]).is_empty():
		return null
	if context.is_editor_preview:
		return InventoryHostFeatureAssembly.new()
	var assembly := preload("res://addons/visual_res_editor_panel/gdbase/inventory/ui/inventory_host/features/inventory_description_feature_assembly.gd").new()
	assembly.configuration = self
	if not assembly.refresh(context):
		assembly.teardown()
		return null
	if active_enabled:
		var processor := ItemDescriptionInputActionProcessor.new()
		processor.describe_item = assembly.describe
		assembly.action_routes = [InventoryInputActionRoute.create(InventoryInputActionIds.DESCRIBE, [processor])]
	return assembly
