@abstract
class_name ItemPart
extends Resource
## 物品数据基础，其子类会被ItemData所拥有,以实现各种类型的物品数据。
## 比如如果 ItemData 拥有 FoodItemData,则该 Item 具有食物功能
## 新增或修改 Part / State 必须遵守 docs/design/规范/物品Part与实例State制作规范.md。

## 稳定实例状态键；动态 Part 必须提供非空且在同一 ItemData 内唯一的键。
@export var instance_state_key: String = ""

## 建议您在子类中重写。
## 因静态方法无法制成抽象方法，且判断该方法为静态方法重要性更高，所以无法强制要求重写。
static func get_part_type()->String:
	return ""

## 是否允许同一类型的多个 Part 共存；单例类型由子类覆写为 false。
func allows_multiple() -> bool:
	return true

## 返回该类的描述面板,由子类实现
func get_description_panel():
	pass

## 获取稳定状态键；子类可结合自身数据生成默认键。
func get_instance_state_key() -> String:
	return instance_state_key

## 创建实例可变状态；静态 Part 默认不创建。
func create_instance_state() -> ItemInstanceState:
	return null

## 纯静态堆叠规划钩子；默认同意且不生成运行时 State。
func plan_stack_merge(_context: ItemStackMergeContext) -> ItemStateMergePlan:
	return ItemStateMergePlan.accept()
