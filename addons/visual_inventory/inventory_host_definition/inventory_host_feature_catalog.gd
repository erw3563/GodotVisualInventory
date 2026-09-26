@tool
extends RefCounted
## 发现领域编辑适配，读取添加声明并执行静态诊断。
const ROOTS := [
	"res://addons/visual_inventory/gdbase/inventory/parts",
	"res://addons/visual_inventory/gdbase/inventory/ui/inventory_host",
	"res://addons/visual_inventory/gdbase/integration/component_inventory",
]
var entries: Array[Dictionary] = []
var errors: Array[String] = []

func refresh(roots: Array = ROOTS) -> void:
	entries.clear()
	errors.clear()
	var paths: Array[String] = []
	for root in roots:
		_scan(root, paths)
	paths.sort()
	var seen: Dictionary = {}
	for path in paths:
		var script: Script = load(path)
		if script == null or not script.can_instantiate():
			errors.append("编辑适配脚本不可创建：" + path)
			continue
		var adapter: Variant = script.new()
		if not adapter is RefCounted or not adapter.has_method("describe") or not adapter.has_method("build") or not adapter.has_method("diagnose"):
			errors.append("编辑适配协议不完整：" + path)
			continue
		var info: Dictionary = adapter.describe()
		var type: Script = info.get("type")
		if not is_feature_type(type) or str(info.get("title", "")).is_empty():
			errors.append("功能类型或名称无效：" + path)
			continue
		var declaration_error := validate_addition_metadata(info)
		if not declaration_error.is_empty():
			errors.append(declaration_error + "：" + path)
			continue
		if seen.has(type):
			errors.append("功能编辑适配重复：" + str(type.get_global_name()))
			entries.erase(seen[type])
			continue
		info["adapter"] = adapter
		info["path"] = path
		seen[type] = info
		entries.append(info)
	entries.sort_custom(func(a: Dictionary, b: Dictionary): return str(a.get("category", "")) + str(a.title) < str(b.get("category", "")) + str(b.title))

func _scan(path: String, paths: Array[String]) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		errors.append("功能编辑目录不可读：" + path)
		return
	for file in directory.get_files():
		if "/editor/" in path + "/" and file.ends_with("_host_feature_editor.gd"):
			paths.append(path.path_join(file))
	for folder in directory.get_directories():
		if not folder.begins_with("."):
			_scan(path.path_join(folder), paths)

static func is_feature_type(type: Script) -> bool:
	if type == null or type.is_abstract() or not type.can_instantiate():
		return false
	var base: Script = type
	while base != null:
		if base == InventoryHostFeatureDefinition:
			return true
		base = base.get_base_script()
	return false

func find(type: Script) -> Dictionary:
	for entry in entries:
		if entry.type == type:
			return entry
	return {}

static func validate_addition_metadata(info: Dictionary) -> String:
	var requirements: Variant = info.get("required_features", [])
	if not requirements is Array:
		return "功能依赖声明应为数组"
	var seen: Dictionary = {}
	for requirement in requirements:
		if not requirement is Dictionary or not requirement.get("type") is Script:
			return "功能依赖需要有效脚本"
		if not is_feature_type(requirement.type):
			return "功能依赖需要可创建的具体功能类型"
		if not requirement.get("before") is bool:
			return "功能依赖需要声明 before 顺序"
		if seen.has(requirement.type):
			return "同一功能依赖重复声明"
		seen[requirement.type] = true
	return ""

func requirements(type: Script) -> Array:
	return find(type).get("required_features", [])

func type_title(type: Script) -> String:
	if type == null:
		return "空功能类型"
	var info := find(type)
	if not info.is_empty():
		return info.title
	return str(type.get_global_name()) if not str(type.get_global_name()).is_empty() else type.resource_path

func title(feature: Resource) -> String:
	if feature == null:
		return "空功能（请删除）"
	var info := find(feature.get_script())
	return info.title if not info.is_empty() else str(feature.get_script().get_global_name()) + "（缺少编辑支持）"

func role_title(role: StringName) -> String:
	for entry in entries:
		var titles: Dictionary = entry.get("role_titles", {})
		if titles.has(role):
			return titles[role]
	return str(role)

func search(query: String, category := "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in entries:
		if not category.is_empty() and entry.get("category", "") != category:
			continue
		var haystack := str(entry.title) + str(entry.get("description", "")) + str(entry.get("keywords", "")) + str(entry.type.get_global_name())
		if query.is_empty() or query.to_lower() in haystack.to_lower():
			result.append(entry)
	return result

func diagnose(layout: Resource, features: Array[InventoryHostFeatureDefinition]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for issue in InventoryHostFeatureValidator.diagnose(features):
		var diagnostic: Dictionary = issue.duplicate()
		diagnostic["error"] = translate_reason(issue.reason)
		if issue.reason == &"inventory_feature_role_conflict":
			diagnostic.error = "%s与%s占用相同身份：%s" % [type_title(issue.type), type_title(issue.other_type), "、".join(issue.roles.map(role_title))]
		result.append(diagnostic)
	for index in features.size():
		var feature := features[index]
		if feature == null:
			continue
		var entry := find(feature.get_script())
		if entry.is_empty() or not entry.has("adapter"):
			result.append({"index": index, "note": "缺少编辑适配，参数只读；运行时依赖待验证。"})
		else:
			for item in entry.adapter.diagnose(feature, layout, features):
				var diagnostic: Dictionary = item.duplicate()
				diagnostic["index"] = index
				result.append(diagnostic)
	return result
static func translate_reason(reason: StringName) -> String:
	return {
		"component_application_must_precede_modifiers": "请将物品组件应用排在物品修饰应用之前。",
		"inventory_feature_missing": "空功能条目，请删除。",
		"inventory_feature_duplicate": "同一具体功能不可重复添加。",
		"inventory_feature_role_declaration_invalid": "功能身份声明含空项或重复项。",
		"cell_appearance_feature_required_before_caller": "需要物品框，且物品框必须排在本功能之前。",
		"shop_input_requires_trade_rules": "消费交互需要显式添加交易规则。",
		"shop_trade_rules_must_precede_input": "请将交易规则排在消费交互之前。",
		"infinite_items_requires_nested_feature": "无消耗拿取需要显式添加嵌套库存。",
		"chess_inventory_undo_requires_shop": "棋局撤回需要显式添加商店交易。",
		"nested_inherited_feature_type_missing": "继承列表含空类型。",
		"nested_inherited_feature_type_duplicate": "继承列表含重复类型。",
		"nested_inherited_feature_type_invalid": "继承类型必须是具体功能脚本。"
	}.get(str(reason), "配置错误：" + str(reason))
