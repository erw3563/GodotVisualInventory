@tool
class_name InventoryAppearanceKeyCatalog
extends Resource
## 项目外观键目录，供编辑页面查询名称与用途。
const Entry = preload("res://addons/visual_res_editor_panel/gdbase/inventory/parts/cell_appearance/editor/inventory_appearance_key_entry.gd")
const BASIC_KEYS: Array[StringName] = [&"placed", &"placeable", &"unplaceable", &"feedback"]
@export var entries: Array[InventoryAppearanceKeyEntry] = []

static func validate_key(key: String) -> String:
	if key.is_empty():
		return "外观键不能为空。"
	for character in key:
		if character.strip_edges().is_empty():
			return "外观键请使用连续字符。"
	return ""

static func basic_catalog() -> InventoryAppearanceKeyCatalog:
	var result := InventoryAppearanceKeyCatalog.new()
	var titles := ["已放置", "可放置", "不可放置", "失败反馈"]
	var descriptions := ["物品已放置时的常驻外观。", "手持物品可以放入目标位置时的预览。", "手持物品无法放入目标位置时的预览。", "操作失败时的短时反馈。"]
	for index in BASIC_KEYS.size():
		var entry := Entry.new()
		entry.id = BASIC_KEYS[index]
		entry.display_name = titles[index]
		entry.description = descriptions[index]
		result.entries.append(entry)
	return result

func find(key: StringName) -> InventoryAppearanceKeyEntry:
	for entry in entries:
		if entry != null and entry.id == key:
			return entry
	return null

func validate() -> String:
	var seen := {}
	for entry in entries:
		if entry == null:
			return "键库存在空条目。"
		var reason := validate_key(str(entry.id))
		if not reason.is_empty():
			return reason
		if seen.has(entry.id):
			return "键库存在重复键：" + str(entry.id)
		if entry.display_name.strip_edges().is_empty():
			return "请填写显示名称：" + str(entry.id)
		seen[entry.id] = true
	for key in BASIC_KEYS:
		if not seen.has(key):
			return "键库缺少基础键：" + str(key)
	return ""
