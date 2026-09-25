@tool
@abstract
class_name InventoryHostFeatureDefinition
extends Resource
## Host 扩展功能的抽象协议：自身是无状态静态模板（.tres 配置资源），
## 由 InventoryHostDefinition.features 显式组合。
##
## 生成什么：本类 @abstract 不直接装配；具体子类在 create_assembly 里为每个
## Host 生成一份独立的有状态 InventoryHostFeatureAssembly——纯输入功能只贡献
## action_routes / action_observers，带运行时的功能还会挂载节点或申请场景共享服务。
##
## 有什么用：组合哪些 Definition，Host 就具备哪些能力。input_priority 决定输入
## 分发顺序（优先级降序、同级按列表顺序）；validate_configuration 在组装期校验
## 功能组合，返回稳定失败原因（空字符串表示合法）。

## 输入分发优先级：降序参与分发，同优先级按 features 列表顺序；组装时拷贝到 Assembly。
@export var input_priority: int = 0

## 声明功能是否支持 Godot 编辑器环境中的装配；由具体功能实现覆盖。
func can_assemble_in_editor() -> bool:
	return false


## 为单个 Host 生成一份独立的有状态装配；返回 null 即装配失败，Host 报错并中止组装。
@abstract func create_assembly(
	context: InventoryHostFeatureContext
) -> InventoryHostFeatureAssembly


## 返回稳定失败原因；空字符串表示配置合法。纯校验不得创建运行时对象。
func validate_configuration(_features: Array[InventoryHostFeatureDefinition]) -> StringName:
	return &""

## 声明本功能独占的职责身份。
func get_exclusive_roles() -> Array[StringName]:
	return []

## 返回当前功能参与双装配绑定事务的准入原因，空值表示允许。
func validate_binding_transaction() -> StringName:
	return &""

func build_operation_policy() -> InventoryOperationPolicy:
	return null
