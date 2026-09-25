@tool
class_name ItemReshapeProcessor
extends RefCounted
## 物品变形的状态准备与命令入口。只在隔离结果中创建 ShapeState。

static func validate_target(item: ItemInstanceData, new_shape: Shape) -> StringName:
	if item == null or item.item_data == null or new_shape == null or new_shape.get_cells().is_empty():
		return &"invalid_reshape_target"
	if not ItemInstanceStateBuilder.validate_existing_states(item.instance_states, item.item_data):
		return &"invalid_reshape_state"
	var old := item.get_shape_state()
	if old != null and not old.is_valid_instance_state():
		return &"invalid_reshape_state"
	if ShapeTransform.are_cell_sets_equal(item.get_local_cells(), new_shape.get_cells()):
		return &"reshape_unchanged"
	return &""

## 唯一的首次变形 State 工厂；不向输入实例安装结果。
static func prepare_state(item: ItemInstanceData, new_shape: Shape, advance_stage: bool = false) -> ItemShapeState:
	if validate_target(item, new_shape) != &"":
		return null
	var previous := item.get_shape_state()
	var result := previous.duplicate_state() as ItemShapeState if previous != null else ItemShapeState.new()
	result.runtime_shape = new_shape.duplicate_deep(Resource.DEEP_DUPLICATE_INTERNAL) as Shape
	result.shape_stage = (previous.shape_stage if previous != null else 0) + (1 if advance_stage else 0)
	return result

## 反应传入预计视图，独立调用读取原实例；身份始终使用原物品。
static func prepare_request(operation_context: InventoryOperationContext,
	inventory: InventoryData, item: ItemInstanceData, new_shape: Shape,
	advance_stage: bool = false, view: InventoryOperationView = null
) -> InventoryOperationRequest:
	var current := view.get_item(item) if view != null else item
	var result := prepare_state(current, new_shape, advance_stage)
	if result == null:
		return null
	var request := InventoryOperationRequest.create(operation_context, InventoryOperationRequest.Type.RESHAPE, item)
	request.source_inventory = inventory
	request.target_inventory = inventory
	request.shape_result = result
	return request

static func plan(operation_context: InventoryOperationContext, inventory: InventoryData, item: ItemInstanceData, new_shape: Shape) -> InventoryOperationDecision:
	var reason := validate_target(item, new_shape)
	if reason != &"":
		return InventoryOperationDecision.reject(reason)
	return InventoryOperationPlanner.plan(prepare_request(operation_context, inventory, item, new_shape))

static func can_reshape(operation_context: InventoryOperationContext, inventory: InventoryData, item: ItemInstanceData, new_shape: Shape) -> bool:
	return plan(operation_context, inventory, item, new_shape).allowed

static func try_reshape(operation_context: InventoryOperationContext, inventory: InventoryData, item: ItemInstanceData, new_shape: Shape) -> bool:
	var decision := plan(operation_context, inventory, item, new_shape)
	return decision.allowed and InventoryOperationCommitter.commit(decision.plan).success
