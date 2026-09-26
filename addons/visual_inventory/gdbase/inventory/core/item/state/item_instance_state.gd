@tool
class_name ItemInstanceState
extends Resource
## 物品实例上某一动态能力的可变状态。模板 Part 保持只读。
## 制作契约、堆叠模型与存档迁移规则见 docs/design/规范/物品Part与实例State制作规范.md。

## 与模板 Part 对应的稳定键，用于存档匹配与合并。
@export var state_key: String = ""

## 深复制本状态，供拆分使用。
func duplicate_state() -> ItemInstanceState:
	return duplicate_deep(Resource.DEEP_DUPLICATE_INTERNAL) as ItemInstanceState

## 同一物品的事务预计事实；默认隔离复制，扩展可保留临时事实和身份。
func duplicate_for_operation() -> ItemInstanceState:
	return duplicate_state()

## 参与事务新鲜度校验但不进入存档的事实。
func get_operation_facts() -> Variant:
	return null

## 返回本 State 借用的只读模板资源，供完整资源图复制保留配置身份。
func get_shared_template_resources(_template: ItemData) -> Array[Resource]:
	return []

## 新实例按初始堆叠数量生成状态；默认数量不影响状态内容。
func prepare_initial_stack_state(_stack_num: int) -> ItemInstanceState:
	return duplicate_state()

## 纯合并规划；未知 State 失败关闭。
func plan_stack_merge(_context: ItemStackMergeContext) -> ItemStateMergePlan:
	return ItemStateMergePlan.reject(&"stack_state_protocol_missing")

## 默认拆分为两份完全隔离的深复制状态。
func plan_stack_split(_context: ItemStackSplitContext) -> ItemStateSplitPlan:
	return ItemStateSplitPlan.accept(duplicate_state(), duplicate_state())

## 与当前版本的同键 Part 对账；无模板派生值的 State 默认无需处理。
func reconcile_with_part(_part: ItemPart) -> bool:
	return true

## 校验本状态的实例事实；可选内建状态同样必须满足自己的数据契约。
func is_valid_instance_state() -> bool:
	return not state_key.is_empty()

## 描述面板过滤用的状态类型；默认取 state_key 冒号前主段。
func get_state_type() -> String:
	if state_key.is_empty():
		return ""
	return state_key.get_slice(":", 0)

## 返回该类的描述控件，由子类实现。
func get_description_panel() -> Array[Control]:
	return []

## 需要模板 Part 上下文才能出描述的 State 覆写此方法；默认忽略 Part 走通用渲染。
func get_description_panel_with_part(_part: ItemPart) -> Array[Control]:
	return get_description_panel()
