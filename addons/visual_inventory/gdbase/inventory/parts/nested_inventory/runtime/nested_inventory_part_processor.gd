class_name NestedInventoryPartProcessor
extends Node
## Host 局部 Part Consumer：严格解析嵌套 Part/State，并把开窗交给场景服务。

var window_service: NestedInventoryWindowService
var parent_features: Array[InventoryHostFeatureDefinition] = []
var inherited_feature_types: Array[Script] = []
var source_host: InventoryHost


## 只消费装配时注入的快照；不创建默认功能，不修改共享 Definition。
func select_child_features() -> Array[InventoryHostFeatureDefinition]:
	var result: Array[InventoryHostFeatureDefinition] = []
	for feature in parent_features:
		if feature != null and inherited_feature_types.has(feature.get_script()):
			result.append(feature)
	return result


func process_action(
	context: InventoryInputActionContext
) -> InventoryInputActionResult:
	if context == null or context.target_item == null or context.target_item.item_data == null:
		return InventoryInputActionResult.pass_result()
	var inventory_part := context.target_item.item_data.get_type_part(
		ItemInventoryPart.get_part_type()
	) as ItemInventoryPart
	if inventory_part == null:
		return InventoryInputActionResult.pass_result()
	var raw_state := context.target_item.peek_state_by_key(
		inventory_part.get_instance_state_key()
	)
	if raw_state == null:
		return InventoryInputActionResult.rejected(&"nested_inventory_state_missing")
	if not raw_state is ItemInventoryState:
		return InventoryInputActionResult.rejected(&"nested_inventory_state_type_invalid")
	var inventory_state := raw_state as ItemInventoryState
	if inventory_state.nested_inventory_data == null:
		return InventoryInputActionResult.rejected(&"nested_inventory_data_missing")
	if inventory_part.nested_panel_definition == null:
		return InventoryInputActionResult.rejected(&"nested_inventory_panel_definition_missing")
	if not is_instance_valid(window_service):
		return InventoryInputActionResult.rejected(&"nested_inventory_window_service_unavailable")
	var owner_node := source_host.inventory_owner if is_instance_valid(source_host) else null
	var window := window_service.open_for_item(
		context.target_item,
		inventory_state.nested_inventory_data,
		inventory_part.nested_panel_definition,
		select_child_features(),
		owner_node,
		source_host
	)
	if window == null:
		return InventoryInputActionResult.rejected(&"nested_inventory_open_failed")
	return InventoryInputActionResult.handled()
