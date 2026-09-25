@tool
class_name InventoryRotateFeatureDefinition
extends InventoryHostFeatureDefinition
## 旋转功能定义。
##
## 生成什么：一个纯输入 Assembly，含 ROTATE（inventory_rotate）动作路由与
## 每 Host 独立的 StandardRotateInputActionProcessor 处理器。
##
## 有什么用：旋转手持或目标物品的朝向（手持时经 HeldItemSession 旋转格网
## 形状），执行走输入控制器的 perform_rotate_action，
## 失败以稳定原因拒绝。子 Host 继承由嵌套功能配置决定。


func create_assembly(_context: InventoryHostFeatureContext) -> InventoryHostFeatureAssembly:
	var assembly := InventoryHostFeatureAssembly.new()
	assembly.action_routes = [InventoryInputActionRoute.create(InventoryInputActionIds.ROTATE, [StandardRotateInputActionProcessor.new()])]
	return assembly

func get_exclusive_roles() -> Array[StringName]:
	return [InventoryHostFeatureRoles.ROTATE]
