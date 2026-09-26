@tool
class_name InventoryQuickTransferFeatureDefinition
extends InventoryHostFeatureDefinition
## 快捷转移功能提供整组、单件输入及本 Host 的免费转移贡献。
## 源中心统一准备两端贡献并执行一次转移，失败返回稳定原因并播放反馈。
## 子 Host 是否继承本功能由嵌套功能配置决定。


func create_assembly(_context: InventoryHostFeatureContext) -> InventoryHostFeatureAssembly:
	var assembly := InventoryHostFeatureAssembly.new()
	assembly.transfer_contributor = InventoryHostTransferContributor.new()
	var processor := StandardQuickTransferInputActionProcessor.new()
	for action_id in [InventoryInputActionIds.QUICK_TRANSFER, InventoryInputActionIds.QUICK_TRANSFER_SINGLE]:
		assembly.action_routes.append(InventoryInputActionRoute.create(action_id, [processor]))
	return assembly

func get_exclusive_roles() -> Array[StringName]:
	return [InventoryHostFeatureRoles.TRANSFER]
