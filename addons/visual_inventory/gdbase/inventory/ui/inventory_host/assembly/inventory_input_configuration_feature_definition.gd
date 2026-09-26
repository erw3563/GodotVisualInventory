@tool
class_name InventoryInputConfigurationFeatureDefinition
extends InventoryHostFeatureDefinition
## 以资源方式声明页面专属输入路由与观察者的通用功能定义。
##
## 生成什么：一个纯数据的 InventoryHostFeatureAssembly——把导出的
## action_routes / action_observers 逐项深拷贝进 Assembly；
## 出现 null 项则装配失败返回 null。
##
## 有什么用：不写脚本、仅靠 .tres 配置即可为 Host 补充额外的输入动作路由与
## 观察者（页面专属交互）；默认不传播到嵌套子 Host。

@export var action_routes: Array[InventoryInputActionRoute] = []
@export var action_observers: Array[InventoryInputActionObserver] = []


func create_assembly(
	_context: InventoryHostFeatureContext
) -> InventoryHostFeatureAssembly:
	var assembly := InventoryHostFeatureAssembly.new()
	for route in action_routes:
		if route == null:
			return null
		assembly.action_routes.append(route.duplicate(true))
	for observer in action_observers:
		if observer == null:
			return null
		assembly.action_observers.append(observer.duplicate(true))
	return assembly
