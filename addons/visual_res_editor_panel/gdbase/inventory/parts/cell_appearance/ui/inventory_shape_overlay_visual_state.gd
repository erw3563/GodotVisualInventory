class_name InventoryShapeOverlayVisualState
extends RefCounted
## 背包形状覆盖层视觉状态策略。
## 负责状态判定、两级样式解析（物品同键条目优先于显式默认条目）与无效操作反馈状态机。

enum PreviewState {
	VALID,
	INVALID,
}

## 默认边框拼图：无边框拼图物品的样式兜底。
var default_cell_appearance_part: ItemCellAppearancePart
## 是否解析常驻样式；关闭后未收到外部请求的物品不返回自身样式（不画边框）。
var show_placed_border := true
## 手持预览样式物品：解析放置预览与预览反馈样式的来源。
var preview_style_item: ItemInstanceData

## 当前预览是否可放置。
var preview_state: PreviewState = PreviewState.VALID
## 是否正在播放无效操作反馈变色。
var is_invalid_feedback_active: bool = false
## 无效操作反馈的版本号，用于取消过期的定时器回调。
var invalid_feedback_version: int = 0
## 为 true 时反馈作用于预览框；为 false 时作用于 invalid_feedback_placed_item。
var invalid_feedback_is_preview: bool = false
## 无效操作反馈所针对的已放置物品；预览反馈时为 null。
var invalid_feedback_placed_item: ItemInstanceData

## 同步视觉状态配置。
func sync_config(
	target_default_cell_appearance_part: ItemCellAppearancePart,
	target_show_placed_border := true
) -> void:
	default_cell_appearance_part = target_default_cell_appearance_part
	show_placed_border = target_show_placed_border

## 设置预览状态。
func set_preview_state(is_valid: bool) -> void:
	preview_state = PreviewState.VALID if is_valid else PreviewState.INVALID

## 开始无效操作反馈并返回当前反馈版本号。
func start_invalid_feedback(item_instance_data: ItemInstanceData = null) -> int:
	invalid_feedback_version += 1
	invalid_feedback_is_preview = item_instance_data == null
	invalid_feedback_placed_item = item_instance_data
	is_invalid_feedback_active = true
	return invalid_feedback_version

## 判断反馈版本是否仍然有效。
func is_feedback_version_valid(target_feedback_version: int) -> bool:
	return target_feedback_version == invalid_feedback_version

## 重置无效操作反馈状态。
func clear_invalid_feedback_state() -> void:
	invalid_feedback_version += 1
	is_invalid_feedback_active = false
	invalid_feedback_is_preview = false
	invalid_feedback_placed_item = null

## 获取已放置物品样式：反馈 > 外部请求 > 常驻；逐键解析。
## 常驻开关关闭且未命中更高状态时返回 null。
func get_placed_item_style(item_instance_data: ItemInstanceData, override_style: InventoryItemVisualStyle = null) -> InventoryItemVisualStyle:
	if _is_placed_item_in_invalid_feedback(item_instance_data):
		return _resolve_self_style(item_instance_data, &"feedback")
	if override_style != null:
		return override_style
	if not show_placed_border:
		return null
	return _resolve_self_style(item_instance_data, &"placed")

## 获取手持预览样式：反馈 > 可放置/不可放置；经 preview_style_item 解析。
func get_preview_style() -> InventoryItemVisualStyle:
	if _is_preview_in_invalid_feedback():
		return _resolve_self_style(preview_style_item, &"feedback")
	if preview_state == PreviewState.VALID:
		return _resolve_self_style(preview_style_item, &"placeable")
	return _resolve_self_style(preview_style_item, &"unplaceable")

## 两级样式解析：物品自身拼图声明优先，落空用默认拼图。
func _resolve_self_style(item: ItemInstanceData, id: StringName) -> InventoryItemVisualStyle:
	return InventoryCellAppearancePartResolver.resolve_style(item, id, default_cell_appearance_part)

func _is_placed_item_in_invalid_feedback(item_instance_data: ItemInstanceData) -> bool:
	return is_invalid_feedback_active \
		and not invalid_feedback_is_preview \
		and item_instance_data == invalid_feedback_placed_item

## 判断预览框是否处于无效操作反馈中。
func _is_preview_in_invalid_feedback() -> bool:
	return is_invalid_feedback_active and invalid_feedback_is_preview
