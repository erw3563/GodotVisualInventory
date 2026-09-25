@tool
class_name QuickReparent
extends Node
## 结构演出件（成为目标控件子节点）：把 [Control] 挂到 [member target] 名下，统一
## 播放契约 [method play] ＋ [signal play_finished]；父子关系当帧改完即完成，宿主
## 同帧继续下一步。
## 位置口径为全局位置冻结：重挂前提炼控件的全局位置，重挂后按新父节点的变换换算回
## 布局坐标，画面停在原处。目标本身是容器时由目标布局接管，重排后的落点由容器
## 决定。
## 本件与 [class QuickFlyTo] 独立：「先飞到目的地、再成为其子节点」由树序里摆两步
## 表达（飞行为前一步，本件为后一步）。重挂后本件离开宿主的直接子节点面，宿主的
## 树序收录、预览与生命周期回收以宿主子树为界，[method restore] 是归还父子关系的
## 入口。
## 编辑器内 `play()` 与自身预览均保持场景结构；按钮校验目标解析与非法父级，重挂
## 只在运行期生效。

signal play_finished

## 要移动的控件；为空则尝试使用本组件的父节点（若为 Control）。
@export var ui: Control
## 接收控件的新父节点。
@export var target: Control
## 归还父级：留空时回退为首次播放前记录的父节点。
@export var restore_parent: Node
## 归还时按记录的父节点与首次播放前的布局位恢复；为 false 时只把父子关系还回去，
## 布局位按全局位置不变的换算写回。
@export var restore_position: bool = true

@export_group("动画预览")
## 仅编辑器生效的单次演出预览：校验驱动控件与目的地配置；运行时调用无副作用。
@export_tool_button("播放一次", "Play") var preview_play_action: Callable = preview_play
@export_tool_button("停止并恢复", "Stop") var preview_stop_action: Callable = preview_stop

## 首次播放前记录的父节点与布局位（[method restore] 的恢复依据）。
var _original_parent: Node = null
var _original_position := Vector2.ZERO
var _has_original := false


## 统一播放契约（宿主经树序时间线驱动）：把 [member ui] 挂到 [member target] 名下并
## 保持全局位置。返回是否受理该步（false = 已处目标父级或配置缺失，宿主据此把该步
## 视为无操作跳过）；完成信号当帧发射。
## 结构改动推到帧末执行：同帧前序演出件（QuickFlyTo）的补间终态落笔先收尾，重挂按
## 那一刻的全局位置冻结，父子关系与落点按本次演出结果收口。
func play() -> bool:
	_resolve_ui()
	if ui == null or target == null or target == ui:
		return false
	# 编辑器（含宿主整树预览）保持场景结构：AnimationPreview 无父子快照，改结构无法恢复。
	if Engine.is_editor_hint():
		return false
	if not ui.is_inside_tree():
		push_warning("QuickReparent：驱动控件不在场景树中，无法重挂。")
		return false
	if ui.get_parent() == target:
		return false
	if _is_descendant_of(target, ui):
		push_warning("QuickReparent：目的地是驱动控件的后代，重挂会构成父子环，跳过。")
		return false
	if not _has_original:
		_original_parent = ui.get_parent()
		_original_position = ui.position
		_has_original = true
	_reparent_deferred.call_deferred(ui)
	play_finished.emit()
	return true


## 帧末执行结构改动：换父级并冻结全局位置——Control 的 reparent 在本工程里按局部位
## 原样迁移（画面会跳），所以按换父级前的全局位置换算写回新父坐标系，画面停在原处。
## 冻结后向目的地广播 NOTIFICATION_CHILD_ORDER_CHANGED：托管排布的布局件
## （如 OrbitTrackKnob 的档位重排）据此按自己的规则重新收口子控件位置，本件的冻结
## 不会盖住目的地的排布结果。
func _reparent_deferred(subject: Control) -> void:
	if not is_instance_valid(subject) or not subject.is_inside_tree() or target == null:
		return
	var global_position := QuickUI.layout_to_global(subject, subject.position)
	subject.reparent(target)
	subject.position = QuickUI.global_to_layout(subject, global_position)
	target.notification(NOTIFICATION_CHILD_ORDER_CHANGED)


## 归还父子关系（幂等）：把 [member ui] 挂回 [member restore_parent] 或记录的原始
## 父节点；[member restore_position] 为真时写回首次播放前的布局位，为假时保持当前
## 全局位置（reparent 自带的父变换换算）。两个父级来源都为空时保持当前父子关系。
func restore() -> void:
	_resolve_ui()
	if ui == null:
		return
	var parent := restore_parent if restore_parent != null else _original_parent
	if parent == null or parent == ui.get_parent():
		return
	if _is_descendant_of(parent, ui):
		push_warning("QuickReparent：归还父级是驱动控件的后代，跳过归还。")
		return
	ui.reparent(parent)
	if restore_position and _has_original:
		ui.position = _original_position


## 当前配置是否可执行（驱动控件与目的地齐备、目的地不是驱动控件自身或驱动控件的
## 后代——后者重挂会构成父子环；已处目标父级的幂等状态由 [method play] 作无操作
## 处理）。
func can_play() -> bool:
	_resolve_ui()
	if ui == null or target == null or target == ui:
		return false
	return not _is_descendant_of(target, ui)


## 若未指定 ui，则当父节点为 Control 时将其作为驱动目标。
func _resolve_ui() -> void:
	if ui != null:
		return
	var p := get_parent()
	if p is Control:
		ui = p as Control


## node 是否为 root 的后代（沿父链上溯；相等单独由调用点判定）。
func _is_descendant_of(node: Node, root: Node) -> bool:
	var current := node.get_parent()
	while current != null:
		if current == root:
			return true
		current = current.get_parent()
	return false


#region 编辑器单次预览

## 仅在编辑器校验一次：目标解析、非法父级与当前父子关系逐项检查；结构改动留待
## 运行期由 [method play] 执行（动画预览机制按属性快照恢复，结构不在快照面内）。
func preview_play() -> void:
	if not Engine.is_editor_hint():
		return
	_resolve_ui()
	if ui == null or target == null:
		push_warning("QuickReparent：驱动控件或目的地缺失（ui / target 未导出），无法预览。")
		return
	if not can_play():
		push_warning("QuickReparent：目的地是驱动控件的后代或与驱动控件相同，无法预览。")
		return
	if ui.get_parent() == target:
		return
	push_warning("QuickReparent：编辑器预览保持场景结构，重挂效果在运行期生效。")


## 编辑器预览按校验路径处理，本入口保持空操作以对齐演出件的统一预览接口。
func preview_stop() -> void:
	pass


func is_previewing() -> bool:
	return false

#endregion
