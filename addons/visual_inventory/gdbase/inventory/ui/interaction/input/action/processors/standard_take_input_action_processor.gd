class_name StandardTakeInputActionProcessor
extends InventoryInputActionProcessor
## 基础拿取；整组与单件共用实例，数量由动作 ID 决定。

func process(context: InventoryInputActionContext) -> InventoryInputActionResult:
	if context == null or not is_instance_valid(context.controller):
		return InventoryInputActionResult.pass_result()
	if context.action_id not in [InventoryInputActionIds.PRIMARY, InventoryInputActionIds.PRIMARY_SINGLE] or context.held_item != null:
		return InventoryInputActionResult.pass_result()
	if not context.controller.can_process_primary_action(context):
		return InventoryInputActionResult.pass_result()
	if ItemSupplyProcessor.uses_infinite_supply(context):
		return supply_to_hand(context, context.action_id == InventoryInputActionIds.PRIMARY_SINGLE)
	if context.controller.try_pick_target(context, context.action_id == InventoryInputActionIds.PRIMARY_SINGLE):
		return InventoryInputActionResult.handled()
	return InventoryInputActionResult.rejected(&"inventory_take_rejected")

## 两种供应输入共用的手持交付；物品生成由无界面的供应 Consumer 完成。
static func supply_to_hand(context: InventoryInputActionContext, single: bool, template_source := false) -> InventoryInputActionResult:
	if context == null or not is_instance_valid(context.controller) or not is_instance_valid(context.held_item_session):
		return InventoryInputActionResult.rejected(&"infinite_items_held_session_missing")
	if context.held_item_session.has_held_item():
		return InventoryInputActionResult.rejected(&"inventory_hand_occupied")
	var source := context.target_item
	var endpoint := context.controller.operation_endpoint
	if source == null or source.item_data == null:
		return InventoryInputActionResult.rejected(&"infinite_items_target_missing")
	if not template_source and (endpoint == null or context.inventory == null or context.inventory != endpoint.inventory or not context.inventory.has_item_instance(source)):
		return InventoryInputActionResult.rejected(&"source_item_missing")
	var reason := ItemTagOperationRule.take_denial(source, endpoint) if endpoint != null else (&"" if template_source else &"missing_operation_endpoint")
	if reason != &"":
		return InventoryInputActionResult.rejected(reason)
	var fresh := ItemSupplyProcessor.create_item(source, single)
	if fresh == null:
		return InventoryInputActionResult.rejected(&"invalid_supply_item")
	context.held_item_session.begin_hold(null, fresh, null, Vector2i(-1, -1), context.controller._get_grid_cell_size())
	return InventoryInputActionResult.handled()
