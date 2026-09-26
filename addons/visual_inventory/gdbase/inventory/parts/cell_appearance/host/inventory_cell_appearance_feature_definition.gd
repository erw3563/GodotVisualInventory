@tool
class_name InventoryCellAppearanceFeatureDefinition
extends InventoryHostFeatureDefinition
## 显式装配格子外观；资源仅保存配置，处理器由每个 Host 的 Assembly 独占。
@export var default_cell_appearance_part: ItemCellAppearancePart
@export var show_placed_border := true
@export var show_place_preview := true
@export var border_width := 3.0
@export var invalid_click_feedback_time := 0.18

func can_assemble_in_editor() -> bool:
	return true

func create_assembly(context: InventoryHostFeatureContext) -> InventoryHostFeatureAssembly:
	if context == null or context.panel_assembly.get_part(InventoryGridPanel) == null:
		return null
	if default_cell_appearance_part != null and not default_cell_appearance_part.validate_appearances().is_empty():
		return null
	var assembly := InventoryCellAppearanceFeatureAssembly.new()
	assembly.configuration = self
	if not assembly.refresh(context):
		assembly.teardown()
		return null
	return assembly
