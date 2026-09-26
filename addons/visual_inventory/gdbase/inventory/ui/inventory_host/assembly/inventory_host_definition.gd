@tool
class_name InventoryHostDefinition
extends Resource
## 单个库存使用终端的完整静态定义；可被多个 Host 安全共享。

@export var layout: InventoryPanelAssemblyDefinition
@export var features: Array[InventoryHostFeatureDefinition] = []


static func create(
	panel: InventoryPanelAssemblyDefinition,
	configured_features: Array = []
) -> InventoryHostDefinition:
	var result := InventoryHostDefinition.new()
	result.layout = panel
	for feature in configured_features:
		if feature != null and not feature is InventoryHostFeatureDefinition:
			push_error("InventoryHostDefinition: 功能类型错误")
			return null
		result.features.append(feature)
	return result


func validate_configuration() -> StringName:
	if layout == null:
		return &"inventory_layout_missing"
	var diagnostics := InventoryHostFeatureValidator.diagnose(features)
	return diagnostics[0].reason if not diagnostics.is_empty() else &""

## 无界面组装根复用同一作者配置，端点生命周期由调用者拥有。
func create_operation_endpoint(inventory: InventoryData) -> InventoryOperationEndpoint:
	if validate_configuration() != &"":
		return null
	var policies: Array = []
	for feature in features:
		var policy := feature.build_operation_policy()
		if policy != null:
			policies.append(policy)
	return InventoryOperationEndpoint.create(inventory, InventoryOperationPolicy.merge(policies))
