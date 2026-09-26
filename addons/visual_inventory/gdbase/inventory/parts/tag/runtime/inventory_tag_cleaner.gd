class_name InventoryTagCleaner
extends RefCounted
## 按标签递归销毁背包内物品；标签选择与子库存遍历始终留在核心之外。


## 销毁背包内全部带指定标签的物品，返回成功销毁数量。
static func remove_items_with_tag(inventory_data: InventoryData, tag_id: String) -> int:
	if inventory_data == null or tag_id.is_empty():
		return 0
	return _remove_items_with_tag(inventory_data, tag_id, {})


static func _remove_items_with_tag(
	inventory_data: InventoryData, tag_id: String, visited_inventories: Dictionary
) -> int:
	if inventory_data == null or visited_inventories.has(inventory_data):
		return 0
	visited_inventories[inventory_data] = true
	var removed_count := 0
	var item_instances := inventory_data.get_item_instances().duplicate()
	for item_instance in item_instances:
		if item_instance == null:
			continue
		var item_data: ItemData = item_instance.item_data
		if item_data == null:
			continue
		for owned_inventory in _query_owned_inventories(item_instance):
			removed_count += _remove_items_with_tag(
				owned_inventory, tag_id, visited_inventories
			)
		var tag_part := item_data.get_type_part(
			ItemTagPart.get_part_type()
		) as ItemTagPart
		if tag_part == null or !tag_part.has_tag(tag_id):
			continue
		if inventory_data.try_destroy_item(InventoryOperationContext.system(), item_instance):
			removed_count += 1
	return removed_count


static func _query_owned_inventories(item: ItemInstanceData) -> Array[InventoryData]:
	var owned: Array[InventoryData] = []
	var query := NestedInventoryQuery.query_owned_inventories(item)
	if query == null or not query.valid:
		push_error("InventoryTagCleaner: 物品所有权查询无效")
		return []
	for inventory in query.inventories:
		if inventory != null and not owned.has(inventory):
			owned.append(inventory)
	return owned
