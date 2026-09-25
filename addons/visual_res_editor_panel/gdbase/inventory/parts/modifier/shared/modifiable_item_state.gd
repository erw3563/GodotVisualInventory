@tool
class_name ModifiableItemState
extends ItemInstanceState
## 带可序列化 Modifier 账本的物品实例状态。具体子类解释逻辑值键与领域校正规则。

@export var modifier_ledger: ModifierLedger = ModifierLedger.new():
	set(value):
		_disconnect_ledger(modifier_ledger)
		modifier_ledger = value if value != null else ModifierLedger.new()
		_connect_ledger(modifier_ledger)

func _init() -> void:
	_connect_ledger(modifier_ledger)

## 使用调用方提供的当前 Part 基础值计算有效值。
func calculate_effective_value(value_key: StringName, part_base_value: Variant) -> Variant:
	return modifier_ledger.calculate(value_key, part_base_value)

## 添加实例永久差异。value_key 必须与 Modifier 的逻辑属性键一致。
func add_value_modifier(
	value_key: StringName,
	modifier: Modifier,
	persistent: bool = true
) -> bool:
	if modifier == null or value_key == StringName():
		return false
	if StringName(modifier.modifier_property_name) != value_key:
		push_error("ModifiableItemState: Modifier 属性键 %s 与目标键 %s 不一致" % [
			modifier.modifier_property_name,
			value_key,
		])
		return false
	modifier.ensure_origin_id()
	return modifier_ledger.add_modifier(modifier, persistent)

## 移除同实例或同血统的实例差异。
func remove_value_modifier(value_key: StringName, modifier: Modifier) -> bool:
	if modifier == null or StringName(modifier.modifier_property_name) != value_key:
		return false
	return modifier_ledger.remove_modifier(modifier)

## 查询指定逻辑值上的实例修饰。
func get_value_modifiers(value_key: StringName) -> Array[Modifier]:
	return modifier_ledger.get_modifiers_for(value_key)

## 子类声明是否支持某逻辑值键。
func supports_value_key(_value_key: StringName) -> bool:
	return false

## 与当前版本 Part 对账；具体 State 负责类型解释与夹紧。
func reconcile_with_part(_part: ItemPart) -> bool:
	return true

## 复制成另一独立物品时保留修饰内容但重分配血统，并恢复账本信号连接。
func duplicate_state() -> ItemInstanceState:
	var duplicated := super() as ModifiableItemState
	if duplicated == null:
		return duplicated
	duplicated._connect_ledger(duplicated.modifier_ledger)
	for modifier in duplicated.modifier_ledger.modifiers:
		if modifier != null:
			modifier.assign_new_origin_id()
	return duplicated

## 同一物品的事务复制保留修饰血统和临时账本。
func duplicate_for_operation() -> ItemInstanceState:
	var result := duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as ModifiableItemState
	result._connect_ledger(result.modifier_ledger)
	for modifier in modifier_ledger.get_runtime_modifiers():
		result.modifier_ledger.add_modifier(modifier.duplicate_deep(Resource.DEEP_DUPLICATE_ALL), false)
	return result

func get_operation_facts() -> Variant:
	return modifier_ledger.get_runtime_modifiers()

## 账本变化时由具体 State 校正当前事实。
func _on_modifier_ledger_changed(_value_key: StringName) -> void:
	pass

func _connect_ledger(ledger: ModifierLedger) -> void:
	if ledger == null:
		return
	if !ledger.ledger_changed.is_connected(_on_modifier_ledger_changed):
		ledger.ledger_changed.connect(_on_modifier_ledger_changed)

func _disconnect_ledger(ledger: ModifierLedger) -> void:
	if ledger == null:
		return
	if ledger.ledger_changed.is_connected(_on_modifier_ledger_changed):
		ledger.ledger_changed.disconnect(_on_modifier_ledger_changed)
