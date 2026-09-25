@tool
class_name QuickTweenFloat
extends Node
## 脚本属性 Float 演出件：把目标 [Control] 上由脚本导出的 float 属性 Tween 到
## [member target_value]。统一播放契约 [method play] ＋ [signal play_finished]；
## [method is_animating] 为播放查询。
## 属性面由目标脚本反射得到：[method list_exported_float_properties] 列出该脚本导出的
## float（含基类脚本的导出项），Inspector 的 [member property_name] 与 [member target_value]
## 据此呈下拉与范围滑条（见 [method _validate_property]）；运行期 [method play] 按同一名单
## 守卫，命中后经 Tween 写值。[Control] 内置表现属性与子属性路径（如 "position:y"）在驱动面
## 之外——显隐归 QuickShow、缩放归 QuickZoom、旋转归 QuickWobble。
## 起点即起播当刻的 authored 属性值：装载期前置态归作者（写进场景），本件的职责面是起播
## 当刻现值到 [member target_value]。
## 所有权契约：写目标脚本导出的 float 属性，布局 position 归位置类演出件、演出租约与落笔
## 管道归宿主中介。
## 编辑器内提供 Inspector「动画预览」单次演出（快照与恢复由共享 AnimationPreview
## 承载，播放经统一 play 方法）；运行时调用保持无副作用。

signal play_finished

## 要驱动的宿主控件；为空则尝试使用本组件的父节点（若为 Control）。
@export var ui: Control:
	set(value):
		ui = value
		if Engine.is_editor_hint():
			notify_property_list_changed()
		_sync_script_watch()

## 目标脚本导出的 float 属性名；Inspector 按目标脚本的导出面呈下拉。
@export var property_name: String = ""

## Tween 终点：play 从当前属性值到达该值。
@export var target_value: float = 0.0

@export_group("播放效果")
## 属性动画时长（秒）；0 视为立即完成（同步发完成信号）。
@export_range(0.0, 2.0, 0.01) var animation_duration: float = 0.25

## 动画过渡类型。
@export var animation_transition: Tween.TransitionType = Tween.TRANS_CUBIC

## 动画缓动类型。
@export var animation_ease: Tween.EaseType = Tween.EASE_OUT

@export_group("动画预览")
## 仅编辑器生效的单次演出预览（快照与恢复由共享 AnimationPreview 承载，播放经
## 统一 play 方法）；运行时调用保持无副作用。
@export_tool_button("播放一次", "Play") var preview_play_action: Callable = preview_play
@export_tool_button("停止并恢复", "Stop") var preview_stop_action: Callable = preview_stop

var _tween: Tween
## 宿主级整树预览会话标记（编辑器内由 QuickUiAnimHost 开关）：开启时等效本组件预览——
## 解锁编辑器隔离与完成信号发射。
var _host_preview_active := false
## 已接线 script_changed 的目标控件：编辑器内目标脚本被替换时重扫属性面。
var _watched_target: Control


func _ready() -> void:
	_sync_script_watch()


## 节点离开场景树时结束预览会话、清理动画并断开目标脚本接线。
func _exit_tree() -> void:
	preview_stop()
	_kill_tween()
	_disconnect_script_watch()


# ---------- 目标脚本属性面 ----------

## 解析驱动目标：优先显式导出的 [member ui]，其次父节点（须为 Control）；无目标返回 null。
func resolve_target() -> Control:
	if ui != null and is_instance_valid(ui):
		return ui
	var parent := get_parent()
	if parent is Control:
		return parent
	return null


## 列出目标脚本导出的 float 属性名：本脚本成员在前、基类脚本成员随后，各自按声明序；
## 目标缺失或未挂脚本时返回空表。
func list_exported_float_properties() -> Array[StringName]:
	var result: Array[StringName] = []
	var script := _target_script()
	if script == null:
		return result
	for info in script.get_script_property_list():
		if _is_drivable_float(info):
			result.append(StringName(str(info.get("name", ""))))
	return result


## 指定导出属性的范围提示：命中 @export_range 时取 min/max/step 与其余标志，剔除既有
## or_greater / or_less 后追加两者——滑条按源范围呈现，并接受越界输入；无范围提示时
## 返回空串。供 [method _validate_property] 与测试读取。
func get_relaxed_range_hint_string(driven_property: String) -> String:
	var info := _find_script_property(driven_property)
	if info.is_empty() or int(info.get("hint", 0)) != PROPERTY_HINT_RANGE:
		return ""
	var source := str(info.get("hint_string", ""))
	if source.is_empty():
		return ""
	var tokens := PackedStringArray()
	for token in source.split(",", false):
		var trimmed := token.strip_edges()
		if trimmed.is_empty() or trimmed == "or_greater" or trimmed == "or_less":
			continue
		tokens.append(trimmed)
	tokens.append("or_greater")
	tokens.append("or_less")
	return ",".join(tokens)


## 声明 Inspector 编辑样式：[member property_name] 下拉列出目标脚本的导出 float，
## [member target_value] 继承源 @export_range 的范围并放宽越界输入。
func _validate_property(property: Dictionary) -> void:
	if property.name == "property_name":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(_property_name_choices())
	elif property.name == "target_value":
		var range_hint := get_relaxed_range_hint_string(property_name)
		if not range_hint.is_empty():
			property.hint = PROPERTY_HINT_RANGE
			property.hint_string = range_hint


## 下拉候选：目标脚本导出 float 的声明序名单；当前值缺席时原样补入，目标脚本改名后
## 已烘焙的属性名仍可读可改。
func _property_name_choices() -> PackedStringArray:
	var choices := PackedStringArray()
	for driven in list_exported_float_properties():
		choices.append(String(driven))
	if not property_name.is_empty() and not choices.has(property_name):
		choices.append(property_name)
	return choices


## 目标脚本；目标缺失或未挂脚本时返回 null。
func _target_script() -> Script:
	var target := resolve_target()
	if target == null:
		return null
	return target.get_script() as Script


## 可驱动谓词：脚本导出面里的 float 属性（编辑器名单与运行期守卫共用）。
func _is_drivable_float(info: Dictionary) -> bool:
	return int(info.get("type", TYPE_NIL)) == TYPE_FLOAT \
		and (int(info.get("usage", 0)) & PROPERTY_USAGE_EDITOR) != 0


## 目标脚本里指定名称的属性信息；未命中返回空字典，供 hint 读取与属性存在性判断。
func _find_script_property(driven_property: String) -> Dictionary:
	var script := _target_script()
	if script == null or driven_property.is_empty():
		return {}
	for info in script.get_script_property_list():
		if str(info.get("name", "")) == driven_property:
			return info
	return {}


# ---------- 编辑器期目标脚本接线 ----------

## 编辑器内接线目标变更：目标控件的 script_changed 触发属性面重扫（目标引用变化与
## 首次就绪各调用一次）。
func _sync_script_watch() -> void:
	if not Engine.is_editor_hint():
		return
	var target := resolve_target()
	if target == _watched_target:
		return
	_disconnect_script_watch()
	_watched_target = target
	if target != null and not target.script_changed.is_connected(_on_target_script_changed):
		target.script_changed.connect(_on_target_script_changed)


func _disconnect_script_watch() -> void:
	if _watched_target != null and is_instance_valid(_watched_target) \
			and _watched_target.script_changed.is_connected(_on_target_script_changed):
		_watched_target.script_changed.disconnect(_on_target_script_changed)
	_watched_target = null


func _on_target_script_changed() -> void:
	notify_property_list_changed()


# ---------- 播放契约 ----------

## 统一播放契约（宿主经树序时间线驱动，散装用法由调用方直调）：从当前属性值到达
## [member target_value]；已处目标且无进行中的动画则无操作。返回是否实际起播或正在播
## （false = 已处目标或属性面不可驱动，宿主据此把该步视为无操作跳过）。时长不大于 0 时
## 立即落位并在调用帧内同步发 [signal play_finished]（调用方须先连接完成信号再起播）。
## 编辑器空闲态拒绝起播（编辑器预览与宿主整树预览会话内放行）。
func play() -> bool:
	if not is_inside_tree():
		push_error("QuickTweenFloat.play() requires a node inside the scene tree.")
		return false
	if Engine.is_editor_hint() and not is_previewing() and not _host_preview_active:
		return false
	var target := resolve_target()
	if target == null:
		push_warning("QuickTweenFloat：目标控件缺失（ui 未导出且父节点不是 Control），无法播放。")
		return false
	if property_name.is_empty():
		push_warning("QuickTweenFloat：未声明要驱动的属性名，无法播放。")
		return false
	if not list_exported_float_properties().has(StringName(property_name)):
		push_warning("QuickTweenFloat：目标脚本未导出 float 属性 %s，无法播放。" % property_name)
		return false
	var current: float = float(target.get(property_name))
	if not is_animating() and is_equal_approx(current, target_value):
		return false
	_kill_tween()
	if animation_duration <= 0.0:
		target.set(property_name, target_value)
		_emit_finished()
		return true
	_tween = create_tween()
	_tween.set_trans(animation_transition).set_ease(animation_ease)
	_tween.tween_property(target, NodePath(property_name), target_value, animation_duration)
	_tween.finished.connect(_on_finished)
	return true


## 属性 Tween 是否进行中（供宿主终态守卫与联动方判断完成时机）。
func is_animating() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()


## 停止进行中的动画并保留当前属性值，完成信号由 [method _emit_finished] 的口径决定。
func _kill_tween() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null


## 完成信号发射口径：运行时与宿主整树预览会话期间外发——编辑器空闲（含本件单次预览）
## 静默；宿主预览的步骤等待依赖完成信号（见预览规范）。
func _emit_finished() -> void:
	if not Engine.is_editor_hint() or _host_preview_active:
		play_finished.emit()


## 动画自然结束时收尾：清空 tween 引用后按上条口径发射完成信号。
func _on_finished() -> void:
	_tween = null
	_emit_finished()


## 宿主级整树预览会话开启（QuickUiAnimHost 编辑器预览调用）：解锁编辑器隔离与完成信号发射。
func _begin_host_preview_session() -> void:
	_host_preview_active = true


## 宿主级整树预览会话结束：杀进行中的属性动画（被驱动属性由宿主的快照采集恢复）。
func _end_host_preview_session() -> void:
	_host_preview_active = false
	_kill_tween()


#region 编辑器单次预览

var _preview := AnimationPreview.new()


## 仅在编辑器播放一次：从 authored 当前属性值到达 [member target_value] 后恢复编辑状态；
## 再次点击从原编辑状态重新开始。起点即 authored 现值，作者把 [member target_value] 设为
## 与现值不同即有可见行程。
func preview_play() -> void:
	if not Engine.is_editor_hint():
		return
	preview_stop()
	_stop_sibling_previews()
	var target := resolve_target()
	if target == null:
		push_warning("QuickTweenFloat：目标控件缺失（ui 未导出且父节点不是 Control），无法预览。")
		return
	var properties: Array[StringName] = []
	properties.append_array(AnimationPreview.PRESENTATION_PROPERTIES)
	properties.append_array(AnimationPreview.GEOMETRY_PROPERTIES)
	if not _preview.begin(target, properties, false):
		return
	# 被驱动属性在共享的两张快照表之外，单独采集以在预览结束时恢复 authored 值。
	if not property_name.is_empty():
		var captured: Array[StringName] = [StringName(property_name)]
		_preview.capture(target, captured)
	_preview_run(_preview.generation)


func is_previewing() -> bool:
	return _preview.is_active()


## 保存前和退出树同步恢复，独立于 Inspector 选择与插件生命周期。
func preview_stop() -> void:
	if not is_previewing():
		return
	_kill_tween()
	_preview.stop()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		preview_stop()


## 同目标互斥：起播前停掉同级其它演出组件的预览会话——两个组件并发预览同一宿主会互相
## 踩对方的快照恢复；宿主（QuickUiAnimHost）名下时先停宿主的预览会话。
func _stop_sibling_previews() -> void:
	var parent := get_parent()
	if parent == null:
		return
	if parent.has_method("preview_stop"):
		parent.call("preview_stop")
	for child in parent.get_children():
		if child != self and child.has_method("preview_stop"):
			child.call("preview_stop")


func _preview_run(token: int) -> void:
	# 等当前布局帧完成；停止或重播后旧轮由代次校验作废。
	await get_tree().process_frame
	if not _preview.is_current(token) or not is_inside_tree():
		return
	play()
	await _preview.wait_tween(self, _tween, token, animation_duration + 2.0)
	if _preview.is_current(token):
		preview_stop()

#endregion
