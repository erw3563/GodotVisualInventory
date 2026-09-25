@tool
extends RefCounted
## 外观键库的加载与合并保存；每次写入检查磁盘版本。
const Catalog = preload("res://addons/visual_res_editor_panel/gdbase/inventory/parts/cell_appearance/editor/inventory_appearance_key_catalog.gd")
const DEFAULT_PATH := "res://addons/visual_res_editor_panel/gdbase/inventory/parts/cell_appearance/editor/presets/appearance_key_catalog.tres"
signal changed
static var _shared: RefCounted
var path := DEFAULT_PATH
var catalog: InventoryAppearanceKeyCatalog
var problem := ""
var fingerprint := ""

static func shared() -> RefCounted:
	if _shared == null:
		_shared = load("res://addons/visual_res_editor_panel/gdbase/inventory/parts/cell_appearance/editor/inventory_appearance_key_catalog_store.gd").new()
		_shared.reload()
	return _shared

func reload() -> void:
	problem = ""
	fingerprint = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	catalog = null
	if fingerprint.is_empty():
		problem = "键库文件缺失：" + path
	else:
		var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if loaded is InventoryAppearanceKeyCatalog:
			problem = loaded.validate()
			if problem.is_empty():
				catalog = loaded
		else:
			problem = "键库格式错误：" + path
	if catalog == null:
		catalog = Catalog.basic_catalog()
	changed.emit()

func refresh_if_changed() -> void:
	var current := FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	if current != fingerprint:
		reload()

func create_catalog() -> String:
	if FileAccess.file_exists(path):
		return "键库文件已存在，请重新载入。"
	var result := _save(Catalog.basic_catalog(), "")
	if result.is_empty():
		reload()
	return result

func save_entry(entry: InventoryAppearanceKeyEntry) -> String:
	if entry == null:
		return "请填写外观键信息。"
	var reason := Catalog.validate_key(str(entry.id))
	if not reason.is_empty():
		return reason
	if entry.display_name.strip_edges().is_empty():
		return "请填写显示名称。"
	reload()
	if not problem.is_empty():
		return problem
	var existing := catalog.find(entry.id)
	if existing != null:
		return "" if existing.same_metadata(entry) else "键名已登记且信息不同：" + str(entry.id)
	if entry.id in Catalog.BASIC_KEYS:
		return "基础键名已保留。"
	var next := catalog.duplicate(true) as InventoryAppearanceKeyCatalog
	next.entries.append(entry.duplicate(true))
	reason = _save(next, fingerprint)
	if reason.is_empty():
		reload()
	return reason

func _save(value: InventoryAppearanceKeyCatalog, expected: String) -> String:
	var reason := value.validate()
	if not reason.is_empty():
		return reason
	if not (path.begins_with("res://") or path.begins_with("user://")) or path.get_extension() != "tres":
		return "请选择项目内的 .tres 键库。"
	var folder := ProjectSettings.globalize_path(path.get_base_dir())
	var directory_error := DirAccess.make_dir_recursive_absolute(folder)
	if directory_error != OK:
		return "创建键库目录失败：" + error_string(directory_error)
	var absolute := ProjectSettings.globalize_path(path)
	var lock_path := absolute + ".lock"
	if DirAccess.make_dir_absolute(lock_path) != OK:
		return "键库正在保存，请稍后重试。"
	var result := _save_locked(value, expected, absolute)
	DirAccess.remove_absolute(lock_path)
	return result

func _save_locked(value: InventoryAppearanceKeyCatalog, expected: String, absolute: String) -> String:
	var current := FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	if current != expected:
		return "键库已被外部修改，请重新载入。"
	var temporary := path.get_basename() + ".pending_" + str(Time.get_ticks_usec()) + ".tres"
	var result := ResourceSaver.save(value, temporary)
	if result != OK:
		return "保存键库失败：" + error_string(result)
	var checked := ResourceLoader.load(temporary, "", ResourceLoader.CACHE_MODE_IGNORE) as InventoryAppearanceKeyCatalog
	if checked == null or not checked.validate().is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return "键库写入校验失败。"
	current = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""
	if current != expected:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return "键库已被外部修改，请重新载入。"
	var backup := absolute + ".previous"
	if FileAccess.file_exists(backup):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return "存在待恢复的键库文件：" + backup
	var had_original := FileAccess.file_exists(path)
	if had_original:
		var uid := ResourceLoader.get_resource_uid(path)
		if uid != -1:
			result = ResourceSaver.set_uid(temporary, uid)
			if result != OK:
				DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
				return "保存键库 UID 失败：" + error_string(result)
		result = DirAccess.rename_absolute(absolute, backup)
		if result != OK:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
			return "保留原键库失败：" + error_string(result)
	result = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), absolute)
	if result != OK:
		var restored := OK
		if had_original:
			restored = DirAccess.rename_absolute(backup, absolute)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return "替换键库失败：" + error_string(result) + ("；原文件位于 " + backup if restored != OK else "")
	if had_original:
		DirAccess.remove_absolute(backup)
	return ""
