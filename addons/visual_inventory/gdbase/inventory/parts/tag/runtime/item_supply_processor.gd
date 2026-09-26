class_name ItemSupplyProcessor
extends RefCounted
## 无状态供应 Consumer；普通拿取按标签调用，无限目录显式调用。
static func is_infinite(item: ItemInstanceData) -> bool:
	return InventoryItemTags.has_tag(item, InventoryItemTags.INFINITE_SUPPLY)

static func uses_infinite_supply(context: InventoryInputActionContext) -> bool:
	if context == null or not is_infinite(context.target_item):
		return false
	if not is_instance_valid(context.controller):
		return false
	var host := context.controller.inventory_host
	if is_instance_valid(host):
		var assembly := host.get_feature_assembly(InventoryOperationRulesFeatureDefinition) as InventoryOperationRulesFeatureAssembly
		if assembly != null:
			return assembly.respect_infinite_supply_tag
	return true

static func create_item(source: ItemInstanceData, single: bool) -> ItemInstanceData:
	if source == null or source.item_data == null:
		return null
	var fresh := ItemInstanceData.new()
	fresh.init(source.item_data, 1 if single else source.get_item_max_num())
	if fresh.num < 1 or not ItemInstanceStateBuilder.validate_existing_states(fresh.instance_states, fresh.item_data):
		return null
	return fresh
