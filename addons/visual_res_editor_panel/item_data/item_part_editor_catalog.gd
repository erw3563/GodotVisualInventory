@tool
extends RefCounted
var entries: Array[Dictionary] = []
var tag_names: Dictionary = {}

func refresh() -> void:
	entries.clear()
	tag_names = InventoryItemTags.DISPLAY_NAMES.duplicate()
	_merge_optional_project_tag_display_names()
	var classes := ProjectSettings.get_global_class_list()
	var by_name := {}
	for info in classes:
		by_name[info.class] = info
	for info in classes:
		var current: String = info.class
		var is_part := false
		while by_name.has(current):
			if current == "ItemPart":
				is_part = true
				break
			current = by_name[current].base
		if not is_part or info.class == "ItemPart":
			continue
		var path: String = info.path
		if not FileAccess.file_exists(path):
			continue
		var adapter_path := path.get_base_dir().path_join("editor").path_join(path.get_file().get_basename() + "_editor.gd")
		if not FileAccess.file_exists(adapter_path):
			continue
		var type: Script = load(path)
		if type.is_abstract() or not type.can_instantiate():
			continue
		var adapter: RefCounted = load(adapter_path).new()
		var data: Dictionary = adapter.describe()
		if data.get("type") != type:
			continue
		data["adapter"] = adapter
		entries.append(data)
		tag_names.merge(data.get("tag_names", {}))
	entries.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.title) < str(b.title))


## 工程若登记了 ProjectItemTags 全局类，合并其 DISPLAY_NAMES 供标签选项显示。
func _merge_optional_project_tag_display_names() -> void:
	for info in ProjectSettings.get_global_class_list():
		if str(info.get("class", "")) != "ProjectItemTags":
			continue
		var path: String = str(info.get("path", ""))
		if path.is_empty() or not FileAccess.file_exists(path):
			return
		var script := load(path) as Script
		if script == null:
			return
		var names: Variant = script.get_script_constant_map().get("DISPLAY_NAMES", {})
		if names is Dictionary:
			tag_names.merge(names)
		return


func find(type: Script) -> Dictionary:
	for entry in entries:
		if entry.type == type:
			return entry
	return {}
