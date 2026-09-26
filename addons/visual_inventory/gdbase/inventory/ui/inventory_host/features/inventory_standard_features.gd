class_name InventoryStandardFeatures
extends RefCounted
## 显式预设组合工厂。Host、布局和控制器不得自动调用。

static func create() -> Array[InventoryHostFeatureDefinition]:
	return [(load("res://addons/visual_inventory/gdbase/inventory/parts/tag/presets/operation_rules.tres") as InventoryOperationRulesFeatureDefinition).duplicate(true), InventoryTakeFeatureDefinition.new(), InventoryPlaceFeatureDefinition.new(), InventoryRotateFeatureDefinition.new(),
		InventoryQuickTransferFeatureDefinition.new(), (load("res://addons/visual_inventory/gdbase/inventory/presets/features/description.tres") as InventoryDescriptionFeatureDefinition).duplicate(true)]

## 独立控制器测试/工具也必须显式绑定功能贡献。
static func create_routes() -> Array[InventoryInputActionRoute]:
	var assemblies: Array[InventoryHostFeatureAssembly] = []
	for feature in [InventoryTakeFeatureDefinition.new(), InventoryPlaceFeatureDefinition.new(), InventoryRotateFeatureDefinition.new(), InventoryQuickTransferFeatureDefinition.new()]:
		assemblies.append(feature.create_assembly(null))
	return InventoryInputConfigurationComposer.compose_routes(assemblies)
