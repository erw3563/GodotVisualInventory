@tool
extends RefCounted
## 提供编辑器布局名称、参数分组与静态诊断。

static func types() -> Array:
	return [GridInventoryPanelAssemblyDefinition, CatalogInventoryPanelAssemblyDefinition, OrbitInventoryPanelAssemblyDefinition, ResourceScanCatalogInventoryPanelAssemblyDefinition, LogicInventoryPanelAssemblyDefinition]
const TITLES := ["▦ GRID 格网", "☷ 库存目录", "◉ ORBIT 轨道", "☷ 资源扫描目录", "逻辑（无视图）"]
const LABELS := {
	"create_background": "背景", "create_grid_panel": "底板", "create_items_panel": "物品层",
	"background_style": "背景样式", "background_material": "背景材质",
	"cell_size": "格子尺寸", "cell_style": "合法格样式", "cell_spacing": "格子间距",
	"show_cell_background": "显示底板", "empty_cell_style": "空洞样式",

	"scan_folder": "扫描目录", "sort_rule": "排序方式", "show_icon": "显示图标",
	"row_style": "行样式", "row_hover_style": "悬停行样式", "row_material": "行材质",
	"icon_modulate": "图标着色", "name_font_color": "名称字体颜色", "name_font_size": "名称字号",
	"count_font_color": "数量字体颜色", "count_font_size": "数量字号",
	"row_height": "每排高度", "min_panel_size": "目录面板最小尺寸", "max_panel_height": "最大高度",
	"show_capacity_header": "显示容量条",
	"orbit_radius": "轨道半径（像素）", "slot_start_angle": "起始角（度）",
	"auto_spin": "自动旋转", "rotation_speed": "旋转速度（弧度/秒）",
	"rotary_drag_enabled": "启用拨盘拖动", "rotary_mouse_button": "拨盘鼠标按钮",
	"rotary_grab_radius_pixels": "抓取半径（像素）", "rotary_hub_radius_pixels": "中心盲区（像素）",
	"snap_back_on_release": "松手回正", "snap_back_duration_seconds": "回正时长（秒）",
	"snap_back_fixed_duration": "使用固定时长", "snap_back_dead_zone_degrees": "回正死区（度）",
	"deal_auto_play": "首次生成自动发牌", "entrance_on_child_added": "新增物品播放入场",
	"deal_duration_seconds": "单件飞行时长（秒）", "deal_stagger_seconds": "错峰间隔（秒）",
	"deal_launch_mode": "起播模式", "deal_transition": "过渡曲线", "deal_ease": "缓动方向"
}

static func type_index(layout: Resource) -> int:
	return types().find(layout.get_script()) if layout != null else -1

const STYLE_KEYS := ["background_style", "cell_style", "empty_cell_style", "row_style", "row_hover_style"]
const MATERIAL_KEYS := ["background_material", "row_material"]
const DETAIL_KEYS := STYLE_KEYS + MATERIAL_KEYS
const GRID_STYLE_KEYS := ["background_style", "cell_style", "empty_cell_style"]
const ORBIT_STYLE_KEYS := ["cell_style"]
const CATALOG_STYLE_KEYS := ["background_style", "row_style", "row_hover_style"]
const SCAN_STYLE_KEYS := ["row_style", "row_hover_style"]

## 标准布局全部表单分组；部件列与编辑列分别取 parts_groups / edit_groups。
static func groups(layout: Resource) -> Dictionary:
	var result := {}
	result.merge(parts_groups(layout))
	result.merge(edit_groups(layout))
	return result

## 左侧上半「部件」：GRID 的背景、底板与物品层开关；目录的背景开关。
static func parts_groups(layout: Resource) -> Dictionary:
	match type_index(layout):
		0:
			return {"部件组成": ["create_background", "create_grid_panel", "create_items_panel"]}
		1:
			return {"部件组成": ["create_background"]}
	return {}

## 左侧下半「编辑」：GRID／目录背景与参数分组；编辑区互斥切换，同一时间只显示一组。
static func edit_groups(layout: Resource) -> Dictionary:
	match type_index(layout):
		0:
			return {
				"背景": ["background_style", "background_material"],
				"底板样式": ["cell_style", "empty_cell_style", "cell_spacing", "show_cell_background"],
				"格子尺寸": ["cell_size"],
			}
		1:
			return {
				"背景": ["background_style", "background_material"],
				"显示": ["sort_rule", "show_icon", "row_height", "show_capacity_header"],
				"行外观": [
					"row_style", "row_hover_style", "row_material", "icon_modulate",
					"name_font_color", "name_font_size", "count_font_color", "count_font_size",
				],
				"尺寸": ["cell_size", "min_panel_size", "max_panel_height"],
			}
		3:
			return {
				"内容": ["scan_folder"],
				"显示": ["sort_rule", "show_icon", "row_height"],
				"行外观": [
					"row_style", "row_hover_style", "row_material", "icon_modulate",
					"name_font_color", "name_font_size", "count_font_color", "count_font_size",
				],
				"尺寸": ["cell_size", "min_panel_size", "max_panel_height"],
			}
		2:
			return {
				"格子样式": ["cell_style", "show_cell_background"],
				"格子尺寸": ["cell_size"],
				"轨道排列": ["orbit_radius", "slot_start_angle"],
				"自动旋转": ["auto_spin", "rotation_speed"],
				"拨盘拖动": ["rotary_drag_enabled", "rotary_mouse_button", "rotary_grab_radius_pixels", "rotary_hub_radius_pixels"],
				"松手回正": ["snap_back_on_release", "snap_back_duration_seconds", "snap_back_fixed_duration", "snap_back_dead_zone_degrees"],
				"发牌与入场": ["deal_auto_play", "entrance_on_child_added", "deal_duration_seconds", "deal_stagger_seconds", "deal_launch_mode", "deal_transition", "deal_ease"],
			}
	return {}

static func is_style_key(key: String, layout: Resource = null) -> bool:
	if layout != null:
		return key in style_keys_for(layout)
	return key in STYLE_KEYS

static func is_material_key(key: String, layout: Resource = null) -> bool:
	if layout != null:
		return key in material_keys_for(layout)
	return key in MATERIAL_KEYS

static func is_detail_key(key: String, layout: Resource = null) -> bool:
	if layout != null:
		return key in detail_keys_for(layout)
	return key in DETAIL_KEYS

## 按布局类型返回字段中文名；目录／扫描目录的 cell_size 表示拿取图标尺寸。
static func field_label(layout: Resource, key: String) -> String:
	var index := type_index(layout)
	if key == "cell_size" and (index == 1 or index == 3):
		return "拿取时物品图标尺寸"
	if key == "cell_style" and index == 2:
		return "格子样式"
	return LABELS.get(key, key)

## GRID、ORBIT、库存目录与资源扫描目录支持右侧嵌套属性（样式或材质）。
static func supports_detail_panel(layout: Resource) -> bool:
	var index := type_index(layout)
	return index == 0 or index == 1 or index == 2 or index == 3


## 当前布局可用的 StyleBox 嵌套键。
static func style_keys_for(layout: Resource) -> Array:
	match type_index(layout):
		0:
			return GRID_STYLE_KEYS.duplicate()
		1:
			return CATALOG_STYLE_KEYS.duplicate()
		2:
			return ORBIT_STYLE_KEYS.duplicate()
		3:
			return SCAN_STYLE_KEYS.duplicate()
	return []


## 当前布局可用的 Material 嵌套键。
static func material_keys_for(layout: Resource) -> Array:
	match type_index(layout):
		0:
			return ["background_material"]
		1:
			return ["background_material", "row_material"]
		3:
			return ["row_material"]
	return []


## 当前布局全部嵌套属性键。
static func detail_keys_for(layout: Resource) -> Array:
	return style_keys_for(layout) + material_keys_for(layout)


## 布局切换或页签重置时的默认嵌套键。
static func default_detail_key(layout: Resource) -> String:
	var keys := detail_keys_for(layout)
	return str(keys[0]) if not keys.is_empty() else ""

static func disabled_reason(layout: Resource, key: String) -> String:
	if layout is GridInventoryPanelAssemblyDefinition or layout is CatalogInventoryPanelAssemblyDefinition:
		if key in ["background_style", "background_material"] and not layout.create_background:
			return "开启背景后可配置。"
	if layout is OrbitInventoryPanelAssemblyDefinition:
		if key == "rotation_speed" and not layout.auto_spin:
			return "启用自动旋转后可调整。"
		if key in ["rotary_mouse_button", "rotary_grab_radius_pixels", "rotary_hub_radius_pixels", "snap_back_on_release"] and not layout.rotary_drag_enabled:
			return "启用拨盘拖动后可调整。"
		if key in ["snap_back_duration_seconds", "snap_back_fixed_duration", "snap_back_dead_zone_degrees"] and (not layout.rotary_drag_enabled or not layout.snap_back_on_release):
			return "启用拨盘拖动与松手回正后可调整。"
		if key == "deal_stagger_seconds" and layout.deal_launch_mode == OrbitTrack.DealLaunchMode.SIMULTANEOUS:
			return "齐发模式不使用错峰间隔；当前值保留。"
	return ""

static func fields(resource: Resource) -> Array[StringName]:
	var result: Array[StringName] = []
	if resource == null:
		return result
	for info in resource.get_property_list():
		if info.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and info.usage & PROPERTY_USAGE_STORAGE:
			result.append(info.name)
	return result

static func clone_layout(layout: InventoryPanelAssemblyDefinition) -> InventoryPanelAssemblyDefinition:
	if layout == null:
		return null
	return layout.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as InventoryPanelAssemblyDefinition

static func fingerprint(resource: Resource) -> String:
	if resource == null:
		return "<null>"
	# Resource 编码包含嵌套资源内容，Script 保留身份；用于检测外部编辑。
	var encoded := ResourceSaver.get_recognized_extensions(resource)
	if encoded.is_empty():
		return str(resource.get_instance_id())
	return _fingerprint_value(resource, {})

static func _fingerprint_value(value: Variant, visited: Dictionary) -> String:
	if value is Script:
		return "script:%s:%s" % [value.resource_path, value.get_instance_id()]
	if value is Resource:
		if visited.has(value.get_instance_id()):
			return "@%s" % visited[value.get_instance_id()]
		visited[value.get_instance_id()] = visited.size()
		var parts: Array[String] = [str(value.get_class()), _fingerprint_value(value.get_script(), visited)]
		for info in value.get_property_list():
			if info.usage & PROPERTY_USAGE_STORAGE and info.name not in ["script", "resource_path"]:
				parts.append(str(info.name) + ":" + _fingerprint_value(value.get(info.name), visited))
		return "|".join(parts)
	if value is Array or value is Dictionary:
		var result := ""
		for key in value:
			result += _fingerprint_value(key, visited) + ";"
			if value is Dictionary:
				result += _fingerprint_value(value[key], visited) + ";"
		return result
	return var_to_str(value)

static func validate(layout: InventoryPanelAssemblyDefinition) -> String:
	if layout == null:
		return "请选择或引用一个布局。"
	if not layout.get_script().can_instantiate():
		return "布局必须是可实例化的具体类型。"
	if layout.cell_size.x < 1.0 or layout.cell_size.y < 1.0:
		return "格子尺寸分量必须至少为 1。"
	if layout is GridInventoryPanelAssemblyDefinition:
		if not layout.create_grid_panel and layout.create_items_panel:
			return "物品层需要底板。请开启底板或关闭物品层。"
		if layout.cell_spacing.x < 0 or layout.cell_spacing.y < 0:
			return "格子间距必须是非负整数。"
	if layout is CatalogInventoryPanelAssemblyDefinition or layout is ResourceScanCatalogInventoryPanelAssemblyDefinition:
		return layout.configuration_problem()
	if layout is OrbitInventoryPanelAssemblyDefinition:
		for key in ["orbit_radius", "rotary_grab_radius_pixels", "rotary_hub_radius_pixels", "snap_back_duration_seconds", "deal_stagger_seconds"]:
			if not is_finite(layout.get(key)) or layout.get(key) < 0.0:
				return "%s必须是非负有限数值。" % LABELS[key]
		if not is_finite(layout.rotation_speed) or not is_finite(layout.slot_start_angle):
			return "旋转速度与起始角必须是有限数值。"
		if layout.rotary_hub_radius_pixels > layout.rotary_grab_radius_pixels:
			return "中心盲区不能大于抓取半径。"
		if layout.deal_duration_seconds <= 0.0 or not is_finite(layout.deal_duration_seconds):
			return "飞行时长必须大于零。"
	return ""
