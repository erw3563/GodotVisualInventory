extends Resource
class_name Modifier
## 负责定位 DataBase 上的目标属性，并挂载一个 VarMachine 执行修改。

## 修饰名字
@export var modifier_name:String
## 要修改的属性名，须与本资源所在 DataBase 子类上的 @export 成员名一致。
@export var modifier_property_name: String
## 修饰是否能够叠加
@export var is_stackable:bool = true
## 血统标记：同一模板实例化/深拷贝出的修饰副本共享同一 id。
## 运行时据此在重挂时认领目标上已挂的同源修饰，避免深拷贝后双重生效；0 表示未标记。
@export var origin_id: int = 0
## 同阶段内优先级（数值越大越先执行）
@export var phase_priority:int = 0
## 执行器：真正的变量修改逻辑由 VarMachine 负责。
@export var machine: VarMachine

static var _next_generated_origin_id: int = int(
	Time.get_unix_time_from_system() * 1000000.0
)

## 统一正向计算入口，供 DataBase 调用。
func calculate_forward(current_value:Variant) -> Variant:
	if machine == null:
		push_warning("Modifier: machine 为空，保持原值")
		return current_value
	return machine.calculate(current_value)

## 是否与另一条修饰同实例或同血统（同一模板实例化/深拷贝出的副本）。
func is_same_lineage(other: Modifier) -> bool:
	if other == null:
		return false
	if self == other:
		return true
	return origin_id != 0 and origin_id == other.origin_id and modifier_name == other.modifier_name

## 为实例持久修饰分配进程内唯一血统；该值随 Modifier 序列化。
func ensure_origin_id() -> int:
	if origin_id == 0:
		assign_new_origin_id()
	return origin_id

## 独立实例复制时重置血统，避免两件物品被运行时误认为同一来源。
func assign_new_origin_id() -> int:
	origin_id = _next_generated_origin_id
	_next_generated_origin_id += 1
	return origin_id
