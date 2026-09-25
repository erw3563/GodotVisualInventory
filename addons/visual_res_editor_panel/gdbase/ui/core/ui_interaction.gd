class_name UIInteraction
extends RefCounted
## 通用 UI 共享交互判定原语：面板系（panel_node）与快捷系（quick_node）共用的
## 热区矩形、热区可见性与鼠标点击判定，纯静态计算、不持有状态、不写任何控件属性。
## 各算法均自面板系实现逐行移植：scaled_zone_rect / unscaled_layout_origin 来自
## ZoomPanel，pose_zone_rect 来自 RotatePanel，viewport_content_rect /
## viewport_clipped_zone_rect 来自 SideBarPanel，is_blank_outside_click /
## is_click_on_zone / zone_active 为四面板同构判定的合并
## （PocketDrawerPanel 特有的「吞点击的 STOP 过滤控件不视为空白」以
## exclude_stop_filtered 参数保真）。

## 热区是否参与交互：指定外部热区控件时完全跟随其可见性；否则用调用方传入的
## 本体热区判定（各面板的本体判定策略不同，由调用方计算后传入）。
static func zone_active(interaction_control: Control, own_zone_visible: bool) -> bool:
	if interaction_control != null:
		return interaction_control.is_visible_in_tree()
	return own_zone_visible


## 还原未缩放布局原点：get_global_position() 含当前缩放绕 pivot 的原点位移，
## 先减去位移得到布局系统摆放的原位置（缩放组件不动真实布局，原点即摆放位）。
static func unscaled_layout_origin(control: Control) -> Vector2:
	return control.get_global_position() - control.pivot_offset * (Vector2.ONE - control.scale)


## 缩放热区：布局矩形与展开/收起目标缩放矩形（绕 pivot）的并集。
## 与当前展开状态无关，默认终点 1、起点 0 时即布局矩形；并集保证收起/展开热区
## 互相覆盖，不因缩放差异来回抖动。
static func scaled_zone_rect(
		control: Control, expanded_scale: Vector2, collapsed_scale: Vector2) -> Rect2:
	var layout_origin := unscaled_layout_origin(control)
	var layout_rect := Rect2(layout_origin, control.size)
	if expanded_scale == Vector2.ONE and collapsed_scale == Vector2.ZERO:
		return layout_rect
	var expanded_origin := layout_origin + control.pivot_offset * (Vector2.ONE - expanded_scale)
	var result := layout_rect.merge(Rect2(expanded_origin, control.size * expanded_scale))
	if collapsed_scale == Vector2.ZERO:
		return result
	var collapsed_origin := layout_origin + control.pivot_offset * (Vector2.ONE - collapsed_scale)
	return result.merge(Rect2(collapsed_origin, control.size * collapsed_scale))


## 姿态热区：布局四角绕轴心旋转到各姿态角后的包围盒并集。
## 与当前动画进度无关，各姿态热区互相覆盖，不因姿态差异来回抖动。
static func pose_zone_rect(control: Control, pose_angles_degrees: Array[float]) -> Rect2:
	if pose_angles_degrees.is_empty():
		return Rect2()
	var corners: Array[Vector2] = []
	for pose_degrees in pose_angles_degrees:
		_append_pose_corners(control, corners, pose_degrees)
	var result := Rect2(corners[0], Vector2.ZERO)
	for corner in corners:
		result = result.expand(corner)
	return result


## 把控件四角变换到指定姿态角（在当前全局变换上绕轴心补转角度差），
## 收集角点供热区取包围盒；对当前姿态角即精确还原布局矩形。
static func _append_pose_corners(
		control: Control, corners: Array[Vector2], pose_degrees: float) -> void:
	var xf := control.get_global_transform()
	var delta := deg_to_rad(pose_degrees) - control.rotation
	var pivot_global := xf * control.pivot_offset
	for corner in [
		Vector2.ZERO,
		Vector2(control.size.x, 0.0),
		Vector2(0.0, control.size.y),
		control.size,
	]:
		corners.append(pivot_global + (xf * corner - pivot_global).rotated(delta))


## 视口内容矩形（客户区，与 Control 全局坐标同一空间，不含系统标题栏）。
static func viewport_content_rect(node: Node) -> Rect2:
	var viewport := node.get_viewport()
	if viewport == null:
		return Rect2()
	return viewport.get_visible_rect()


## 视口裁剪热区：布局矩形 ∩ 视口内容矩形——控件滑出屏幕的部分不算热区。
static func viewport_clipped_zone_rect(control: Control) -> Rect2:
	return control.get_global_rect().intersection(viewport_content_rect(control))


## 栏外空白判定：鼠标不在来源控件热区内时，点击处无悬浮控件视为空白；
## 来源控件自身/子孙、切换按钮树、其它按钮均不抢点击。
## exclude_stop_filtered 开启时，吞点击的 STOP 过滤控件（其它背包/面板）也不视为
## 空白（PocketDrawerPanel 语义）；默认关闭（ZoomPanel / RotatePanel / SideBarPanel 语义）。
static func is_blank_outside_click(
		source: Control,
		toggle_button: BaseButton,
		mouse_inside_source: bool,
		exclude_stop_filtered := false) -> bool:
	if mouse_inside_source:
		return false
	var viewport := source.get_viewport()
	if viewport == null:
		return false
	var hovered_control := viewport.gui_get_hovered_control()
	if hovered_control == null:
		return true
	# 点在来源控件内（含子控件）时不视为空白
	if hovered_control == source or source.is_ancestor_of(hovered_control):
		return false
	# 外部切换按钮交给按钮自己处理，避免先收起再被 toggle 拉开
	if toggle_button != null and (
			hovered_control == toggle_button
			or toggle_button.is_ancestor_of(hovered_control)):
		return false
	# 其它外部按钮视为非空白，不抢点击
	if hovered_control is BaseButton:
		return false
	# 吞点击的 STOP 过滤控件同样不抢
	if exclude_stop_filtered and hovered_control.mouse_filter == Control.MOUSE_FILTER_STOP:
		return false
	return true


## 外部热区点击判定：鼠标在热区内时，命中热区控件（含子孙）或热区下的空白
## 视为点击热区；热区上的其它交互控件不抢。
static func is_click_on_zone(
		source: Control,
		interaction_control: Control,
		mouse_inside_zone: bool) -> bool:
	if interaction_control == null:
		return false
	if not mouse_inside_zone:
		return false
	var viewport := source.get_viewport()
	if viewport == null:
		return false
	var hovered_control := viewport.gui_get_hovered_control()
	if hovered_control == null:
		return true
	return hovered_control == interaction_control \
			or interaction_control.is_ancestor_of(hovered_control)
