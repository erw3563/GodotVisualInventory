@tool
class_name ItemInstanceData
extends Resource
## ItemInstanceData 是物品的数据。它负责记录物品会经常变化的数据。

signal num_changed(num:int)
signal dir_changed(direction: Vector2)
signal shape_changed

## 同类实例共享的只读物品模板。
@export var item_data:ItemData:
	set(value):
		if item_data != value:
			instance_states.clear()
			_has_reconciled_instance_states = false
		item_data = value
## 本件动态 Part 与形状的实例状态集合。
@export var instance_states: Array[ItemInstanceState] = []
## 物品数量
@export var num:int = 1:
	set(value):
		num = clampi(value,0,get_item_max_num())
		num_changed.emit(num)
## 物品朝向，取值为 RIGHT、DOWN、LEFT、UP 之一。
@export var dir: Vector2 = Vector2.RIGHT:
	set(value):
		dir = ShapeTransform.normalize_cardinal_dir(value)
		dir_changed.emit(dir)

var _is_populating_instance_states: bool = false
var _has_reconciled_instance_states: bool = false

## 声明实例 State 的存储与编辑器显示规则。
func _validate_property(property: Dictionary) -> void:
	if property.name == "instance_states":
		property.usage = property.usage & ~PROPERTY_USAGE_EDITOR

## 编辑器中不执行运行时组件/修饰逻辑，避免调用非 @tool Resource 的实例方法。
func _should_skip_runtime_state_logic() -> bool:
	return Engine.is_editor_hint()

## 初始化 ItemInstanceData ，该方法需要手动调用。
func init(item_data_:ItemData,num_:int = 1) -> void:
	item_data = item_data_
	num = num_
	if _should_skip_runtime_state_logic():
		return
	_populate_instance_states_from_item_data()

## 从 ItemData 构建必需的动态 Part 状态；已有状态按稳定键严格对账。
func _populate_instance_states_from_item_data() -> void:
	if _is_populating_instance_states:
		return
	if _should_skip_runtime_state_logic() or item_data == null:
		return
	if _has_reconciled_instance_states:
		return
	_is_populating_instance_states = true
	if instance_states.is_empty():
		instance_states = ItemInstanceStateBuilder.build(item_data, num)
	_has_reconciled_instance_states = ItemInstanceStateBuilder.reconcile_states(
		instance_states,
		item_data,
		num
	)
	_is_populating_instance_states = false

## 显式使用当前 ItemData.parts 对账全部实例 State；读档和模板热换后可安全重复调用。
func reconcile_instance_states() -> bool:
	if _should_skip_runtime_state_logic() or item_data == null:
		return false
	if _is_populating_instance_states:
		return false
	_is_populating_instance_states = true
	var result := ItemInstanceStateBuilder.reconcile_states(instance_states, item_data, num)
	_has_reconciled_instance_states = result
	_is_populating_instance_states = false
	return result

## 内建可选状态的声明；不构造原型或补建实例状态。
static func get_builtin_state_schema() -> Dictionary:
	return {ItemShapeState.SHAPE_STATE_KEY: {
		"part": null, "state_script": ItemShapeState, "prototype": null, "required": false,
	}}

## 仅查询已有变形事实，不补建状态，也不要求模板含 ShapePart。
func get_shape_state() -> ItemShapeState:
	return peek_state_by_key(ItemShapeState.SHAPE_STATE_KEY) as ItemShapeState

## 惰性补齐状态，含已有 Shape 时仍按模板补缺失项。
func _ensure_instance_states_ready() -> void:
	if _should_skip_runtime_state_logic():
		return
	if item_data == null:
		return
	_populate_instance_states_from_item_data()

## 尝试将物品与自身堆叠
func try_merge_item(inventory_item_data:ItemInstanceData)->bool:
	_ensure_instance_states_ready()
	if inventory_item_data != null:
		inventory_item_data._ensure_instance_states_ready()
	var plan := ItemStackOperationPlanner.plan_merge(self, inventory_item_data)
	return ItemStackOperationCommitter.commit_merge(plan)

## 只读检查两件物品的模板与实例 State 是否允许合并。
func can_merge_item(other_item: ItemInstanceData) -> bool:
	_ensure_instance_states_ready()
	if other_item != null:
		other_item._ensure_instance_states_ready()
	return ItemStackOperationPlanner.plan_merge(self, other_item).allowed

## 按稳定键查找状态。
func _get_state_by_key(state_key: String) -> ItemInstanceState:
	for instance_state in instance_states:
		if instance_state != null and instance_state.state_key == state_key:
			return instance_state
	return null

## 公开的稳定键 State 查询；会先补齐并对账。
func get_state_by_key(state_key: StringName) -> ItemInstanceState:
	_ensure_instance_states_ready()
	return _get_state_by_key(String(state_key))

## 只读查看已存在 State，不惰性补齐；规划/Rule 用于避免查询期间修改实例。
func peek_state_by_key(state_key: StringName) -> ItemInstanceState:
	return _get_state_by_key(String(state_key))

## 向指定 State 逻辑值添加实例永久修饰。
func add_state_value_modifier(
	state_key: StringName,
	value_key: StringName,
	modifier: Modifier
) -> bool:
	var state := get_state_by_key(state_key) as ModifiableItemState
	if state == null or !state.supports_value_key(value_key):
		push_error("ItemInstanceData: State %s 不存在或不支持逻辑值 %s" % [state_key, value_key])
		return false
	return state.add_value_modifier(value_key, modifier)

## 从指定 State 逻辑值移除同实例或同血统修饰。
func remove_state_value_modifier(
	state_key: StringName,
	value_key: StringName,
	modifier: Modifier
) -> bool:
	var state := get_state_by_key(state_key) as ModifiableItemState
	if state == null or !state.supports_value_key(value_key):
		return false
	return state.remove_value_modifier(value_key, modifier)

## 将自身一分为二
func split(split_num:int)->ItemInstanceData:
	_ensure_instance_states_ready()
	return ItemStackOperationCommitter.commit_split(
		ItemStackOperationPlanner.plan_split(self, split_num)
	)

## 只复制已有状态，不在源实例上触发惰性初始化。
func _duplicate_instance_states() -> Array[ItemInstanceState]:
	var duplicated_states: Array[ItemInstanceState] = []
	for instance_state in instance_states:
		if instance_state == null:
			continue
		duplicated_states.append(instance_state.duplicate_state())
	return duplicated_states

## 同一物品的事务预计事实，使用 State 的中性复制协议保留临时事实。
func duplicate_for_operation() -> ItemInstanceData:
	var result := ItemInstanceData.new()
	result.item_data = item_data
	result.num = num
	result.dir = dir
	for state in instance_states:
		if state != null:
			result.instance_states.append(state.duplicate_for_operation())
	if _has_reconciled_instance_states:
		result._mark_instance_states_ready()
	else:
		result.reconcile_instance_states()
	return result

## 深拷贝为独立物品；target_num 缺省（-1）时与原实例份数一致。
func duplicate_instance(target_num: int = -1) -> ItemInstanceData:
	if target_num < 0:
		target_num = num
	target_num = maxi(1, mini(target_num, get_item_max_num()))
	var duplicated := ItemInstanceData.new()
	duplicated.init(item_data, target_num)
	if _should_skip_runtime_state_logic():
		return duplicated
	duplicated.dir = dir
	duplicated.instance_states = _duplicate_instance_states()
	if _has_reconciled_instance_states:
		duplicated._mark_instance_states_ready()
	else:
		# 规划会为预演复制刚反序列化的实例；补缺只能发生在副本上。
		duplicated.reconcile_instance_states()
	return duplicated

## 确定的堆叠结果整体替换 State 后，标记无需再次补齐或对账。
func _mark_instance_states_ready() -> void:
	_has_reconciled_instance_states = true

func is_full()->bool:
	return num >= get_item_max_num()

#region 获取数据方法
## 获取物品数据
func get_item_data()->ItemData:
	return item_data
## 获取物品名字
func get_item_name()->String:
	if item_data == null:
		return ""
	return item_data.item_name
## 获取物品图标纹理
func get_item_icon()->Texture2D:
	if item_data == null:
		return null
	return item_data.icon
## 获取当前的物品数量
func get_item_num()->int:
	return num
## 获取单堆最大可堆叠数量。
func get_item_max_num()->int:
	if item_data == null:
		return 1
	return max(1, item_data.max_num)
## 获取还能放置的物品数量
func get_remain_space_num()->int:
	return get_item_max_num() - num
## 获取物品描述文本
func get_item_description()->String:
	if item_data == null:
		return ""
	return item_data.item_description
## 获取本件当前局部轮廓格子；runtime_shape 优先，否则回退模板。
func get_local_cells() -> Array[Vector2i]:
	var shape_state := get_shape_state()
	if shape_state != null:
		return shape_state.get_local_cells()
	if item_data != null:
		var template_shape := item_data.get_shape()
		if template_shape != null:
			var template_cells := template_shape.get_cells()
			if !template_cells.is_empty():
				return template_cells
	return [Vector2i.ZERO]
## 按指定局部格子、朝向与中心格预览占据，不修改本件状态。
func get_cells_for_local_cells(
	local_cells: Array[Vector2i],
	custom_direction: Vector2,
	custom_center: Vector2i = Vector2i.ZERO
) -> Array[Vector2i]:
	return ShapeTransform.transform_local_cells(local_cells, custom_direction, custom_center)
## 按指定轮廓预览占据格子，不修改本件状态。
func get_cells_for_shape(
	shape: Shape,
	custom_direction: Vector2,
	custom_center: Vector2i = Vector2i.ZERO
) -> Array[Vector2i]:
	return get_cells_for_local_cells(
		ShapeTransform.cells_from_shape(shape), custom_direction, custom_center
	)
## 获取该物品当前旋转状态下占据的格子坐标。
func get_cells(custom_center: Vector2i = Vector2i.ZERO) -> Array[Vector2i]:
	return get_cells_for_local_cells(get_local_cells(), dir, custom_center)
## 获取该物品在指定朝向状态下占据的格子坐标，不会修改当前 dir。
func get_cells_with_dir(custom_direction: Vector2, custom_center: Vector2i = Vector2i.ZERO) -> Array[Vector2i]:
	return get_cells_for_local_cells(get_local_cells(), custom_direction, custom_center)
## 获取物品中心坐标。返回的坐标会根据 custom_center 进行坐标转换
func get_center_cell(custom_center: Vector2i = Vector2i.ZERO) -> Vector2i:
	return ShapeTransform.origin_cell(dir, custom_center)
## 获取物品的正方形大小
func get_shape_size()->Vector2i:
	return ShapeTransform.bounding_size(get_local_cells())
## 获取未旋转局部轮廓的包围盒（min 角可为负）；显示层用作预旋转基准。
func get_local_shape_rect()->Rect2i:
	return ShapeTransform.bounding_rect(get_local_cells())
## 获取按当前朝向旋转后局部轮廓的包围盒；占据格 = 旋转格 + 锚点平移，
## 故「锚点格 + 本包围盒 min」即物品实际占格的包围盒左上格。
func get_rotated_shape_rect()->Rect2i:
	return ShapeTransform.bounding_rect(ShapeTransform.rotate_cells_by_dir(get_local_cells(), dir))
#endregion

## 校验处理器提供的变形结果；模型不创建 ShapeState。
func is_valid_reshape_result(result: ItemInstanceState) -> bool:
	if result == null or result.get_script() != ItemShapeState or not result.is_valid_instance_state():
		return false
	var shape_result := result as ItemShapeState
	var previous := get_shape_state()
	if previous != null and (result == previous or shape_result.runtime_shape == previous.runtime_shape):
		return false
	if item_data != null and shape_result.runtime_shape == item_data.get_shape():
		return false
	var stage := previous.shape_stage if previous != null else 0
	return shape_result.shape_stage == stage or shape_result.shape_stage == stage + 1

#region 判断
func is_same_item(item_instance_data:ItemInstanceData)->bool:
	if item_instance_data == null:
		return false
	return item_instance_data.get_item_data() == item_data
#endregion
