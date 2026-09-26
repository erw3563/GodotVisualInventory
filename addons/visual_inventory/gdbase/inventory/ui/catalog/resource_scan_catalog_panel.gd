@tool
class_name ResourceScanCatalogPanel
extends ItemCatalogPanel
## 资源模板目录。扫描缓存与代表实例由面板独占，不属于任何真实库存。

@export_dir var scan_folder := "":
	set(value):
		if scan_folder == value:
			return
		scan_folder = value
		_source_dirty = true
		rebuild_rows()

var scan_count := 0
var scan_problem := ""
var _source_dirty := true
var _item_datas: Array[ItemData] = []
var _template_instances: Dictionary = {}

func refresh_display() -> void:
	_source_dirty = true
	rebuild_rows()

func _collect_groups() -> void:
	_groups.clear()
	if _source_dirty:
		_item_datas.clear()
		_template_instances.clear()
		_source_dirty = false
		scan_problem = ItemResourceScanner.validate_folder(scan_folder)
		if not scan_folder.is_empty():
			scan_count += 1
			_item_datas = ItemResourceScanner.scan_item_datas(scan_folder)
	for item_data in _item_datas:
		var group := CatalogItemGroup.new()
		if group.try_add_instance(_get_template_instance(item_data)):
			_groups.append(group)
	_finalize_collected_groups()
	if _empty_hint != null:
		_empty_hint.text = "请选择扫描目录" if scan_folder.is_empty() else (
			scan_problem if not scan_problem.is_empty() else "目录为空")

func _compare_groups(a, b) -> bool:
	var order: int = a.display_name.casecmp_to(b.display_name)
	if order == 0:
		return a.item_data.resource_path < b.item_data.resource_path
	return order > 0 if sort_rule == SortRule.NAME_DESC else order < 0

func _format_group_count(_group) -> String:
	return ""

func _get_template_instance(item_data: ItemData) -> ItemInstanceData:
	if not _template_instances.has(item_data):
		var template := ItemInstanceData.new()
		template.init(item_data, 1)
		_template_instances[item_data] = template
	return _template_instances[item_data]

func _get_occupy_map_for_capacity() -> OccupyMap:
	return null

func _try_connect_inventory_data_signal() -> void:
	pass

func _try_disconnect_inventory_data_signal() -> void:
	pass

func _exit_tree() -> void:
	_groups.clear()
	_sync_instance_num_signals()
	_template_instances.clear()
	_item_datas.clear()
	_source_dirty = true
