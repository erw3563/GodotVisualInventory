@tool
class_name ItemResourceScanner
extends RefCounted
## 递归读取资源目录中的物品模板；无默认内容目录或业务动作。

static func validate_folder(folder: String) -> String:
	if folder.is_empty():
		return ""
	var normalized := folder.simplify_path()
	if not normalized.begins_with("res://") or normalized.contains(".."):
		return "扫描目录必须位于 res://：%s" % folder
	if not DirAccess.dir_exists_absolute(normalized):
		return "扫描目录不存在：%s" % folder
	return ""

static func scan_item_datas(folder: String) -> Array[ItemData]:
	var result: Array[ItemData] = []
	if folder.is_empty():
		return result
	var problem := validate_folder(folder)
	if not problem.is_empty():
		push_warning(problem)
		return result
	_scan(folder.simplify_path(), result, {}, {})
	result.sort_custom(_compare_item_by_name)
	return result

static func _scan(folder: String, result: Array[ItemData], seen: Dictionary, visited: Dictionary) -> void:
	if visited.has(folder):
		return
	visited[folder] = true
	var directory := DirAccess.open(folder)
	if directory == null:
		push_warning("ItemResourceScanner：无法打开目录 %s" % folder)
		return
	for child in directory.get_directories():
		if not child.begins_with(".") and not directory.is_link(child):
			_scan(folder.path_join(child), result, seen, visited)
	# ResourceLoader 列举逻辑资源名，导出后同样保留 .tres/.res 路径。
	for file in ResourceLoader.list_directory(folder):
		if file.get_extension().to_lower() not in ["tres", "res"]:
			continue
		var path := folder.path_join(file)
		var resource := load(path)
		if resource is not ItemData:
			push_warning("ItemResourceScanner：%s 不是 ItemData，已跳过" % path)
			continue
		if not seen.has(resource):
			seen[resource] = true
			result.append(resource)

static func _compare_item_by_name(a: ItemData, b: ItemData) -> bool:
	var order := a.item_name.casecmp_to(b.item_name)
	return a.resource_path < b.resource_path if order == 0 else order < 0
