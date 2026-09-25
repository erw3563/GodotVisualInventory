@tool
class_name QuickUiAnimHost
extends Node
## 快捷系演出宿主：单向时间线播放器——按直接子节点树序播放名下演出件的一趟
## 序列，一个宿主只负责一个方向；入场与离场由两个独立宿主表达（离场宿主的
## animate_entrance 置 false，由调用方显式播放）。同时兼任位置落笔中介——接收
## QuickDrag / QuickMousePlace 提交的位置，统一经 [method place] 按落笔意图分发
## （[enum QuickUI.PlaceIntent]：交互与定位落笔过 stage 链加工、演出端点直写），再过
## stage 链加工后唯一落笔——stage 即子节点中实现 apply_place 契约者，按场景树顺序
## 依次加工；位置演出件（QuickPopIn / QuickPopOut / QuickFlyTo）自行 tween 控件布局
## position，宿主在步骤完成后把落点经管道登记为最终休息位、取消播放时收回其写入。
## 双宿主场景由调用方指定唯一中介宿主：交互件的 placer 引用指向它，
## 非中介宿主纯做时间线。
##
## QuickDrag 与 QuickConstraints 为散装组件、不受宿主生成管理：drag 手工把 placer
## 指到宿主即参与交互落笔仲裁，constraints 手工挂宿主名下即作 stage——均经鸭子
## 契约参与中介，无需宿主知晓类型。
## 演出件是多实例语义——「节点即动画」：参数面＝演出组件的 @export，动作面＝播放
## 契约，多步＝多实例；经添加按钮或 [method add_performance] 逐个追加，树面板拖动
## 排序即编排、嵌套进同播组即并行、插入延时步骤即间隔。QuickShow 处理显隐，
## QuickPopIn / QuickPopOut 处理位置进出，QuickMousePlace 处理鼠标处定位，
## QuickZoom 处理缩放，QuickWobble 处理旋转晃动，QuickRotate 处理转到目标角，
## QuickFlyTo 处理前往目标控件位置，QuickReparent 处理成为目标控件子节点，
## QuickTweenFloat 处理目标脚本导出 float 属性的 Tween。
## get_pop_in / get_pop_out /
## get_zoom / get_wobble / get_rotate / get_show / get_place / get_fly_to / get_reparent / get_tween_float
## 取树序第一个，全量访问走 [method get_performances]。
##
## 步骤契约：统一播放契约（play 方法＋play_finished 信号，QuickDelay / QuickShow /
## QuickMousePlace / QuickZoom / QuickWobble / QuickRotate / QuickMask / QuickPopIn / QuickPopOut /
## QuickFlyTo / QuickTweenFloat 实现）。未实现该契约的节点只占结构位置不占时间线。
##
## 树序时间线：play 按直接子节点在树中的顺序逐步播放（每步等上一步完成），同播组
## 内演出子节点同帧齐播、全部完成才算该步结束。执行带代次令牌（重播作废旧序列，
## 组件状态按各自终态守卫）、完成信号＋有界等待兜底（外部中止路径不死等，超时
## 前进并警告）；取消路径（重播 / 交互落笔 / 宿主或步骤节点退出树）收回进行中步骤
## 的位置写入，剩余步骤不再播放，经 [signal finished](interrupted) 收尾。
##
## 装载归属：宿主名下的演出节点不自入场（_ready 同帧抑制 animate_entrance，自入场
## 只属于散装用法）；宿主等布局稳定后按总开关 animate_entrance 播放整条树序（生成
## 时是否入场）。装载铺场：_ready 对实现 prepare_play 契约的演出件铺起播前置态
## （如 QuickShow 目标为显示时先瞬时隐藏，弥合装载帧到起播前的闪现）。运行时后补
## 的演出件不自动入场，由调用方显式 play。
##
## 对齐 InventoryHost 装配模式：编辑器里用导出按钮生成子节点并随场景烘焙保存，
## 运行时恢复引用。演出件之间相互隔离：组件配对（zoom↔rotate 信号等）全部由作者
## 显式表达——导出引用、代码连接或序列化连接；组合的先后与并行由树序结构表达。
## 播放方式：检查器的按钮引用导出把外部控件的 pressed 接到本宿主 play——绑定即
## 接上、换绑转移连接、退出树断连，编辑期与运行时同款接线，场景序列化连接由该
## 引用取代。
## 各组件的行为参数直接在生成的子节点上调，播放效果组为唯一的宿主统一下发项
## （见该组注释）。散装 QuickNode 可脱离宿主单独配置——QuickMousePlace 的 placer
## 为空时直接设置控件位置，语义等价于空管道。

## 目标控件（生成演出件的初始目标，全部组件共同驱动的宿主 UI）；为空时兜底解析
## 父节点（须为 Control，与 QuickPopIn / QuickPopOut / QuickZoom 的 ui 解析同款）。目标引用只在
## 生成时赋一次初值，之后以各件烘焙 / 作者指定的引用为准；运行时更改仅影响后续
## 生成与宿主自身解析（预览目标等）。
@export var ui: Control

@export_group("播放方式")
## 外部按钮引用：为宿主提供按下即播放的触发入口，绑定即自动接上该按钮的 pressed
## 信号，换绑先断旧按钮再连新按钮，退出树时断连（按钮所有权归调用方）。
@export var play_button: BaseButton:
	set(value):
		_disconnect_play_button()
		play_button = value
		_connect_play_button()
@export_group("")

## 演出件类型（[method add_performance] 工厂入参）。
enum PerformanceKind {
	POP_IN,       ## QuickPopIn：从当前位到目标位置（入场，驱动位置）
	POP_OUT,      ## QuickPopOut：从当前位到目标位置（离场，驱动位置）
	ZOOM,         ## QuickZoom：原点缩放展开 / 收起
	WOBBLE,       ## QuickWobble：旋转晃动反馈
	ROTATE,       ## QuickRotate：转到目标角
	MASK,         ## QuickMask：纹理遮罩显隐（可选 ui 耦合：生成时赋宿主目标、遮罩矩形跟随；无目标自呈现）
	SHOW,         ## QuickShow：显隐演出（目标属性声明显示或隐藏）
	PLACE,        ## QuickMousePlace：鼠标处定位（一次性 PLACEMENT 落笔）
	FLY_TO,       ## QuickFlyTo：前往目标控件位置（tween 驱动位置，走演出租约）
	REPARENT,     ## QuickReparent：成为目标控件子节点（改父子结构，保持全局位置）
	TWEEN_FLOAT,  ## QuickTweenFloat：目标脚本导出 float 属性的 Tween（写脚本自有属性面）
	PARALLEL,     ## QuickParallel：同播组（组内演出子节点同帧齐播）
	DELAY,        ## QuickDelay：延时步骤（间隔表达）
}

@export_group("演出件")
## 按类型追加演出子节点（编辑器生成结果随场景烘焙保存；多实例合法，树面板拖动
## 排序即编排）。运行时等价工厂为 [method add_performance]。
@export_tool_button("同播组") var add_parallel_action = _add_parallel_performance
@export_tool_button("延时步骤") var add_delay_action = _add_delay_performance
@export_tool_button("Zoom 缩放") var add_zoom_action = _add_zoom_performance
@export_tool_button("Show 显隐") var add_show_action = _add_show_performance
@export_tool_button("Wobble 晃动") var add_wobble_action = _add_wobble_performance
@export_tool_button("Rotate 旋转") var add_rotate_action = _add_rotate_performance
@export_tool_button("Mask 遮罩显隐") var add_mask_action = _add_mask_performance
@export_tool_button("Place 鼠标定位") var add_place_action = _add_place_performance
@export_tool_button("FlyTo 飞向控件") var add_fly_to_action = _add_fly_to_performance
@export_tool_button("Reparent 成为子节点") var add_reparent_action = _add_reparent_performance
@export_tool_button("TweenFloat 脚本属性") var add_tween_float_action = _add_tween_float_performance
@export_tool_button("PopIn 弹入") var add_pop_in_action = _add_pop_in_performance
@export_tool_button("PopOut 弹出") var add_pop_out_action = _add_pop_out_performance

@export_group("播放效果")
## 跨演出组件（QuickPopIn / QuickPopOut / QuickZoom / QuickWobble / QuickRotate）统一的高频播放参数，是「宿主
## 不镜像行为参数」原则的显式例外（仅限跨组件高频项）：生成子节点时作为初始值
## 下发，运行时更改会重新下发给已存在的全部演出子节点；场景装载期不下发（就绪
## 守卫同 ui），烘焙子节点的细调值以场景为准——唯一例外是 animate_entrance：
## 宿主名下的演出节点恒 false（播放归属宿主，装载期即覆盖烘焙值），本开关只驱动
## 宿主自己的树序播放（生成时是否播放）。
@export var animate_entrance: bool = true:
	set(value):
		animate_entrance = value
		_apply_performance_params_if_ready()

@export_range(0.0, 2.0, 0.01) var animation_duration: float = 0.25:
	set(value):
		animation_duration = value
		_apply_performance_params_if_ready()

@export var animation_transition: Tween.TransitionType = Tween.TRANS_BACK:
	set(value):
		animation_transition = value
		_apply_performance_params_if_ready()

@export var animation_ease: Tween.EaseType = Tween.EASE_OUT:
	set(value):
		animation_ease = value
		_apply_performance_params_if_ready()

@export_group("动画预览")
## 仅编辑器生效的单趟演出预览（快照与恢复由共享 AnimationPreview 承载）：按当前
## 树序播放一趟，结束后恢复编辑状态；运行时调用无副作用。
@export_tool_button("播放一次", "Play") var preview_play_action: Callable = preview_play
@export_tool_button("停止并恢复", "Stop") var preview_stop_action: Callable = preview_stop

## 树序播放走完时发出：自然走完 interrupted = false；被取消（重播 / 交互落笔 /
## 宿主或步骤节点退出树）为 true。全部步骤无操作时当帧发出 false。
signal finished(interrupted: bool)

## 树序播放代次令牌：每次起播 / 取消自增，运行中的协程据此作废。
var _play_generation := 0

## 进行中步骤的演出节点（同播组为多员）：取消路径据此收回它们对控件位置的写入。
var _active_step_nodes: Array[Node] = []

## 步骤等待超时的固定余量（秒）：覆盖帧调度抖动，慢机器上误推进仅提前走下一步
## 且留有 push_warning 痕迹。
const _STEP_TIMEOUT_MARGIN := 1.0

var show: QuickShow
var mouse_place: QuickMousePlace
var pop_in: QuickPopIn
var pop_out: QuickPopOut
var zoom: QuickZoom
var wobble: QuickWobble
var rotate: QuickRotate
var fly_to: QuickFlyTo
var reparent: QuickReparent
var tween_float: QuickTweenFloat


func _ready() -> void:
	if not Engine.is_editor_hint():
		_suppress_performance_auto_entrance()
		_prepare_performances()
	_cache_quick_nodes()
	_connect_play_button()
	if not Engine.is_editor_hint():
		_schedule_host_playback()


func _exit_tree() -> void:
	preview_stop()
	_disconnect_play_button()
	_cancel_tree_playback()


## 演出件工厂：按类型创建演出子节点并追加到宿主末尾——唯一命名（如 QuickZoom_2，
## 名字仅保证唯一、不承载语义，排序与删除经树面板），绑目标、以宿主
## 播放效果为初始值（子件 animate_entrance 恒 false）。
## 返回新节点供代码设其余导出；需要目标的类型在目标缺失时警告并返回 null。
## 运行时后补的演出件不自动播放，由调用方显式 play。
func add_performance(kind: PerformanceKind) -> Node:
	var target := _resolve_ui()
	var node: Node = null
	match kind:
		PerformanceKind.POP_IN:
			if target == null:
				push_warning("QuickUiAnimHost：目标控件缺失（ui 未导出且父节点不是 Control），无法添加 QuickPopIn。")
				return null
			node = QuickPopIn.new()
			node.ui = target
			_assign_performance_params(node)
		PerformanceKind.POP_OUT:
			if target == null:
				push_warning("QuickUiAnimHost：目标控件缺失（ui 未导出且父节点不是 Control），无法添加 QuickPopOut。")
				return null
			node = QuickPopOut.new()
			node.ui = target
			_assign_performance_params(node)
		PerformanceKind.ZOOM:
			if target == null:
				push_warning("QuickUiAnimHost：目标控件缺失（ui 未导出且父节点不是 Control），无法添加 QuickZoom。")
				return null
			node = QuickZoom.new()
			node.ui = target
			_assign_performance_params(node)
		PerformanceKind.WOBBLE:
			if target == null:
				push_warning("QuickUiAnimHost：目标控件缺失（ui 未导出且父节点不是 Control），无法添加 QuickWobble。")
				return null
			node = QuickWobble.new()
			node.ui = target
			_assign_performance_params(node)
		PerformanceKind.ROTATE:
			if target == null:
				push_warning("QuickUiAnimHost：目标控件缺失（ui 未导出且父节点不是 Control），无法添加 QuickRotate。")
				return null
			node = QuickRotate.new()
			node.ui = target
			_assign_performance_params(node)
		PerformanceKind.MASK:
			# 可选目标耦合：有目标即赋 ui（遮罩矩形跟随）；目标空缺时自呈现
			# （摆位由作者 / 代码负责）。
			node = QuickMask.new()
			if target != null:
				node.ui = target
			_assign_performance_params(node)
		PerformanceKind.SHOW:
			if target == null:
				push_warning("QuickUiAnimHost：目标控件缺失（ui 未导出且父节点不是 Control），无法添加 QuickShow。")
				return null
			node = QuickShow.new()
			node.control = target
			_assign_performance_params(node)
		PerformanceKind.PLACE:
			if target == null:
				push_warning("QuickUiAnimHost：目标控件缺失（ui 未导出且父节点不是 Control），无法添加 QuickMousePlace。")
				return null
			node = QuickMousePlace.new()
			node.control = target
			node.placer = self
			_assign_performance_params(node)
		PerformanceKind.FLY_TO:
			if target == null:
				push_warning("QuickUiAnimHost：目标控件缺失（ui 未导出且父节点不是 Control），无法添加 QuickFlyTo。")
				return null
			node = QuickFlyTo.new()
			node.ui = target
			_assign_performance_params(node)
		PerformanceKind.REPARENT:
			if target == null:
				push_warning("QuickUiAnimHost：目标控件缺失（ui 未导出且父节点不是 Control），无法添加 QuickReparent。")
				return null
			node = QuickReparent.new()
			node.ui = target
			_assign_performance_params(node)
		PerformanceKind.TWEEN_FLOAT:
			if target == null:
				push_warning("QuickUiAnimHost：目标控件缺失（ui 未导出且父节点不是 Control），无法添加 QuickTweenFloat。")
				return null
			node = QuickTweenFloat.new()
			node.ui = target
			_assign_performance_params(node)
		PerformanceKind.PARALLEL:
			node = QuickParallel.new()
		PerformanceKind.DELAY:
			node = QuickDelay.new()
	# 唯一命名（首个用类型基名，其后 _2、_3…——仅保证唯一、不承载语义；Godot 手工
	# 命名不容 '@'，故后缀用下划线而非编辑器自动唯一化的 @N）。
	node.name = _unique_performance_name(_performance_base_name(kind))
	_add_managed(node)
	# 运行时后补的件补铺起播前置态（烘焙路径由 _ready 的装载铺场覆盖）。
	if node.has_method("prepare_play"):
		node.call("prepare_play")
	_cache_quick_nodes()
	return node


# ---------- 访问器 ----------

## 获取显隐演出件：树序第一个；全量访问走 [method get_performances]。
func get_show() -> QuickShow:
	_cache_quick_nodes()
	return show


## 获取鼠标处定位演出件：树序第一个；全量访问走 [method get_performances]。
func get_place() -> QuickMousePlace:
	_cache_quick_nodes()
	return mouse_place


## 获取入场位置演出件：树序第一个；全量访问走 [method get_performances]。
func get_pop_in() -> QuickPopIn:
	_cache_quick_nodes()
	return pop_in


## 获取离场位置演出件：树序第一个；全量访问走 [method get_performances]。
func get_pop_out() -> QuickPopOut:
	_cache_quick_nodes()
	return pop_out


## 获取缩放组件：树序第一个；全量访问走 [method get_performances]。
func get_zoom() -> QuickZoom:
	_cache_quick_nodes()
	return zoom


## 获取晃动组件：树序第一个；全量访问走 [method get_performances]。
func get_wobble() -> QuickWobble:
	_cache_quick_nodes()
	return wobble


## 获取旋转组件：树序第一个；全量访问走 [method get_performances]。
func get_rotate() -> QuickRotate:
	_cache_quick_nodes()
	return rotate


## 获取飞向控件件：树序第一个；全量访问走 [method get_performances]。
func get_fly_to() -> QuickFlyTo:
	_cache_quick_nodes()
	return fly_to


## 获取重挂件：树序第一个；全量访问走 [method get_performances]。
func get_reparent() -> QuickReparent:
	_cache_quick_nodes()
	return reparent


## 获取脚本属性 Tween 件：树序第一个；全量访问走 [method get_performances]。
func get_tween_float() -> QuickTweenFloat:
	_cache_quick_nodes()
	return tween_float


## 返回宿主名下全部演出节点（树序扁平：直接子节点中的演出组件＋同播组一层内的
## 演出子节点，含延时步骤）。交互件与同播组结构节点不在其列。
func get_performances() -> Array:
	return _collect_performance_nodes()


# ---------- 树序时间线播放 ----------

## 播放一趟树序时间线：按直接子节点在树中的顺序依次执行，每步等上一步完成再走
## 下一步。步骤为演出组件（实现播放契约的直接子节点）或同播组（组内演出子节点
## 同帧齐播）；交互件与未知节点只占结构位置不占时间线。已处终态的步骤无操作即
## 完成；完成时刻发 [signal finished]。重播触发新代次、旧序列剩余步骤不再播放。
func play() -> void:
	# 编辑器空闲不起播；整树预览会话期间放行（见文末预览区）。
	if Engine.is_editor_hint() and not _preview.is_active():
		return
	_play_generation += 1
	_run_tree_playback(_play_generation)


func _run_tree_playback(generation: int) -> void:
	for child in get_children():
		if generation != _play_generation or not is_inside_tree():
			_emit_playback_finished(true)
			return
		if not is_instance_valid(child) or not child.is_inside_tree():
			_emit_playback_finished(true)
			return
		if child is QuickParallel:
			if not await _play_parallel_step(child, generation):
				_emit_playback_finished(true)
				return
		elif _is_step_node(child):
			if not await _play_step_node(child, generation):
				_emit_playback_finished(true)
				return
	_emit_playback_finished(false)


func _emit_playback_finished(interrupted: bool) -> void:
	# 完成信号仅在运行时发射——编辑器空闲不外发；整树预览会话期间放行（预览编排
	# 的有限等待依赖完成信号，见预览规范）。
	if Engine.is_editor_hint() and not _preview.is_active():
		return
	finished.emit(interrupted)


## 统一播放契约判定：同时具备 play 方法与 play_finished 信号者。
func _uses_unified_play(node: Node) -> bool:
	return node.has_method("play") and node.has_signal("play_finished")


## 步骤节点判定：实现统一播放契约者占时间线；交互件与未知节点只占结构位置。
func _is_step_node(node: Node) -> bool:
	return _uses_unified_play(node)


## 播放单个子步骤（非同播组）：直调统一播放契约 play 并等 play_finished；
## 完成后登记位置落点并解除进行中标记。返回 false 表示序列被取消。
func _play_step_node(node: Node, generation: int) -> bool:
	_track_active_steps([node])
	var step_ok: bool = await _play_step(
		node, &"play", node.play_finished, _step_wait_timeout(node), generation
	)
	_active_step_nodes.erase(node)
	if step_ok:
		_register_step_final_rest(node, true)
	return step_ok


## 执行单个演出步骤并等待完成：先挂完成信号再起播（兼容时长 0 的同步完成路径——
## 信号在调用帧内发射）。返回 false 表示序列被取消；已处终态（play 返回 false）
## 无操作即完成；有界等待超时则前进并警告（RotationWobble.stop/abort 等外部中止
## 路径明确不发 finished，靠超时兜底不死等）。
func _play_step(node: Node, method: StringName, completion: Signal, timeout: float, generation: int) -> bool:
	var fired: Array = [false]
	var on_done := func(_signal_arg = null) -> void: fired[0] = true
	completion.connect(on_done, CONNECT_ONE_SHOT)
	var started: bool = node.call(method)
	if not started:
		if not fired[0] and completion.is_connected(on_done):
			completion.disconnect(on_done)
		return true
	if fired[0]:
		# 同步完成路径（时长 0 等在调用帧内发射）：直接返回，避免 await 已完成协程
		# 让帧——保证后续步骤同帧起播、全部终态当帧走完。
		return true
	return await _await_step_completion(node, fired, timeout, generation)


## 步骤等待超时：按件推导（QuickDelay 取 duration、QuickMousePlace / QuickReparent 取
## 固定余量、QuickShow / QuickPopIn / QuickPopOut / QuickFlyTo / QuickZoom / QuickMask /
## QuickTweenFloat 取
## animation_duration、QuickWobble 取 (wobble_sequence.size()+1)*animation_duration、QuickRotate 取 animation_duration），
## 加固定余量。
func _step_wait_timeout(node: Node) -> float:
	if node is QuickDelay:
		return node.duration + _STEP_TIMEOUT_MARGIN
	if node is QuickMousePlace or node is QuickReparent:
		return _STEP_TIMEOUT_MARGIN
	if node is QuickShow:
		return node.animation_duration + _STEP_TIMEOUT_MARGIN
	if node is QuickPopIn or node is QuickPopOut or node is QuickFlyTo:
		return node.animation_duration + _STEP_TIMEOUT_MARGIN
	if node is QuickZoom:
		return node.animation_duration + _STEP_TIMEOUT_MARGIN
	if node is QuickWobble:
		return float(node.wobble_sequence.size() + 1) * node.animation_duration + _STEP_TIMEOUT_MARGIN
	if node is QuickRotate:
		return node.animation_duration + _STEP_TIMEOUT_MARGIN
	if node is QuickMask:
		return node.animation_duration + _STEP_TIMEOUT_MARGIN
	if node is QuickTweenFloat:
		return node.animation_duration + _STEP_TIMEOUT_MARGIN
	return 2.0 + _STEP_TIMEOUT_MARGIN


## 有界等待步骤完成：逐帧检查完成标志；代次变更 / 宿主或步骤节点退出树 → 取消
## （返回 false，剩余步骤不再播放）；超时 → 警告并前进（返回 true，序列继续）。
func _await_step_completion(node: Node, fired: Array, timeout: float, generation: int) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0) + 1
	while not fired[0]:
		if generation != _play_generation:
			return false
		if not is_inside_tree() or not is_instance_valid(node) or not node.is_inside_tree():
			return false
		if Time.get_ticks_msec() >= deadline:
			push_warning("QuickUiAnimHost：演出步骤 %s 等待完成超时（%.2f 秒），跳过继续后续步骤。" % [node.name, timeout])
			return true
		await get_tree().process_frame
	return true


## 执行同播组步骤：组内演出子节点同帧起播（先挂完成信号再触发播放），统一有界
## 等待全部完成才算该步结束；已处终态的成员无动作不阻塞，起播的成员在完成后登记
## 位置落点。嵌套组与深层（曾孙及以下）节点不参与（警告留痕）。
func _play_parallel_step(group: Node, generation: int) -> bool:
	var members := _parallel_members(group)
	if members.is_empty():
		return true
	# 同帧起播全部成员并收集待完成项。
	var pending: Array = []
	var started_members: Array = []
	for member in members:
		var completion: Signal = member.play_finished
		var fired: Array = [false]
		var on_done := func(_signal_arg = null) -> void: fired[0] = true
		completion.connect(on_done, CONNECT_ONE_SHOT)
		var started: bool = member.play()
		if not started:
			if not fired[0] and completion.is_connected(on_done):
				completion.disconnect(on_done)
			continue
		pending.append([member, fired])
		started_members.append(member)
	_track_active_steps(started_members)
	if pending.is_empty():
		return true
	var step_ok: bool = await _await_parallel_completion(pending, _max_step_timeout(members), generation)
	for member in started_members:
		_active_step_nodes.erase(member)
		if step_ok:
			_register_step_final_rest(member, true)
	return step_ok


## 有界等待同播组全部成员完成：逐帧检查完成标志；代次变更 / 宿主或任一成员退出树
## → 取消（返回 false，剩余步骤不再播放）；超时 → 警告并前进（返回 true）。
func _await_parallel_completion(pending: Array, timeout: float, generation: int) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0) + 1
	while not _all_parallel_steps_done(pending):
		if generation != _play_generation or not is_inside_tree():
			return false
		for entry in pending:
			var member: Node = entry[0]
			if not is_instance_valid(member) or not member.is_inside_tree():
				return false
		if Time.get_ticks_msec() >= deadline:
			push_warning("QuickUiAnimHost：同播组等待完成超时（%.2f 秒），跳过继续。" % timeout)
			return true
		await get_tree().process_frame
	return true


func _all_parallel_steps_done(pending: Array) -> bool:
	for entry in pending:
		if not entry[1][0]:
			return false
	return true


func _max_step_timeout(members: Array) -> float:
	var result := 0.0
	for member in members:
		result = maxf(result, _step_wait_timeout(member))
	return result


## 收集同播组的有效成员：组直接子节点中实现统一播放契约者。
func _parallel_members(group: Node) -> Array:
	var members: Array = []
	for child in group.get_children():
		if child is QuickParallel:
			push_warning("QuickUiAnimHost：同播组 %s 内嵌套同播组 %s，内层组不参与播放。" % [group.name, child.name])
			continue
		if not _is_step_node(child):
			continue
		members.append(child)
	if _has_deep_performance(group, 0):
		push_warning("QuickUiAnimHost：同播组 %s 内嵌套超过一层（曾孙及以下），深层演出节点不参与播放。" % group.name)
	return members


## 组内是否存在嵌套超过一层的演出节点 / 同播组（depth ≥ 2 的步骤节点）。
func _has_deep_performance(node: Node, depth: int) -> bool:
	for child in node.get_children():
		if depth >= 1 and (child is QuickParallel or _is_step_node(child)):
			return true
		if _has_deep_performance(child, depth + 1):
			return true
	return false


## 取消进行中的树序播放（剩余步骤不再播放）：重播、交互落笔、宿主退出树等路径
## 调用；收回进行中步骤对控件位置的写入，运行中的等待协程在下一帧检测到代次变更
## 后以 interrupted 收尾。
func _cancel_tree_playback() -> void:
	_play_generation += 1
	for node in _active_step_nodes:
		if is_instance_valid(node) and node.has_method("interrupt"):
			node.call("interrupt")
	_active_step_nodes.clear()


## 登记进行中步骤的演出节点：同播组多名成员按调用顺序追加。
func _track_active_steps(nodes: Array) -> void:
	for node in nodes:
		if not _active_step_nodes.has(node):
			_active_step_nodes.append(node)


## 步骤完成后的位置登记：位置演出件在自身步骤完成后把落点经管道登记为最终休息位
## （marks 移动后仍被钳回合法区）。QuickFlyTo 在此重新落一次定型的落点，
## QuickPopIn 把刚到达的目标位交给 stage 链。
func _register_step_final_rest(node: Node, started: bool) -> void:
	if not started:
		return
	if node is QuickFlyTo:
		var fly := node as QuickFlyTo
		if fly.ui != null:
			place(fly.ui, fly.target_global(), QuickUI.PlaceIntent.PLACEMENT)
	elif node is QuickPopIn:
		var pop := node as QuickPopIn
		if pop.ui != null:
			place(pop.ui, pop.target_global(), QuickUI.PlaceIntent.PLACEMENT)


# ---------- 装载归属 ----------

## 宿主名下的演出节点不自入场：接线期（_ready 同帧）对实现 animate_entrance 字段的
## 演出子节点写 false（装载期守卫的显式例外——该字段以宿主口径覆盖烘焙值）。
## 散装用法不受影响。
func _suppress_performance_auto_entrance() -> void:
	for node in _collect_performance_nodes():
		if "animate_entrance" in node:
			node.animate_entrance = false


## 装载铺场：对实现 prepare_play 契约的演出件铺起播前置态，弥合装载帧到起播前的
## 表现闪现（前置态由各件定义，如 QuickShow 目标为显示时先瞬时隐藏）。
func _prepare_performances() -> void:
	for node in _collect_performance_nodes():
		if node.has_method("prepare_play"):
			node.call("prepare_play")


## 宿主自己的播放：布局稳定后按总开关走整条树序（生成时是否播放）。
func _schedule_host_playback() -> void:
	if not animate_entrance:
		return
	_host_playback_async()


func _host_playback_async() -> void:
	await QuickUI.layout_settled(self)
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if not animate_entrance or Engine.is_editor_hint():
		return
	play()


# ---------- 播放效果下发 ----------

## setter 侧入口：就绪后延迟到帧末统一下发——脚本热重载的属性恢复期，后声明的
## 成员可能尚未初始化（立即读取会以 Nil 赋给占位子节点报错）；延迟也把同帧
## 多次改动合并成一次下发。生成路径不经此（add_performance 直接赋值，成员彼时已就绪）。
func _apply_performance_params_if_ready() -> void:
	if not is_node_ready():
		return
	_apply_performance_params.call_deferred()


## 把播放效果下发给已存在的全部演出子节点（含烘焙档恢复与多实例；延时步骤等
## 无对应字段的节点经属性探测自然跳过）。
func _apply_performance_params() -> void:
	for node in _collect_performance_nodes():
		_assign_performance_params(node)


## 播放效果在组件上同名同型，生成与下发共用一个赋值入口；animate_entrance 恒 false
## ——宿主独占播放（宿主名下该字段失效，其余参数装载期仍以烘焙细调值为准）。
func _assign_performance_params(node) -> void:
	if "animate_entrance" in node:
		node.animate_entrance = false
	if "animation_duration" in node:
		node.animation_duration = animation_duration
	if "animation_transition" in node:
		node.animation_transition = animation_transition
	if "animation_ease" in node:
		node.animation_ease = animation_ease


# ---------- 位置落笔中介 ----------

## 位置落笔入口：写位置组件提交位置的统一加工口，提交的任意控件同等生效。按意图
## 分发——INTERACTIVE 与 PLACEMENT 经 stage 链加工后唯一落笔（末笔写布局 position，
## 经 QuickUI 与父变换换算，不受目标 pivot/scale 影响），PRESENTATION 直写（演出
## 端点钳回屏内会毁掉入场 / 收起动画）。
## 返回最终落笔位置。INTERACTIVE 落笔同时取消进行中的树序播放（用户接管交互，
## 剩余步骤不再播放）。
func place(control: Control, proposed: Vector2, intent: QuickUI.PlaceIntent = QuickUI.PlaceIntent.PLACEMENT) -> Vector2:
	if control == null:
		return proposed
	match intent:
		QuickUI.PlaceIntent.INTERACTIVE:
			_cancel_tree_playback()
			return _place_through_stages(control, proposed)
		QuickUI.PlaceIntent.PRESENTATION:
			# 演出端点不加工：钳回屏内会毁掉入场 / 收起动画。
			control.position = QuickUI.global_to_layout(control, proposed)
			return proposed
		QuickUI.PlaceIntent.PLACEMENT, _:
			return _place_through_stages(control, proposed)


## 提议经 stage 链加工后唯一落笔：stage 即子节点中实现 apply_place 契约者，
## 按场景树顺序依次加工（散装 QuickConstraints 由作者摆位，钳制类 stage 宜摆在首位）；
## 末笔在链尾统一执行，无 stage 时原样落笔。
func _place_through_stages(control: Control, proposed: Vector2) -> Vector2:
	var result := proposed
	for child in get_children():
		if child.has_method("apply_place"):
			result = child.apply_place(control, result)
	control.position = QuickUI.global_to_layout(control, result)
	return result


# ---------- 内部工具 ----------

## 解析目标控件：优先显式导出，其次父节点（须为 Control）。
func _resolve_ui() -> Control:
	if ui != null:
		return ui
	var parent := get_parent()
	if parent is Control:
		return parent
	return null


## 挂到宿主名下并按场景归属持久化（编辑器生成结果随场景保存）。
func _add_managed(node: Node) -> void:
	add_child(node)
	if owner:
		node.owner = owner
	else:
		node.owner = self


## 从已有子节点恢复运行时引用（编辑器生成的节点随场景保存后，脚本变量不持久）：
## 演出件（QuickPopIn / QuickPopOut / QuickZoom / QuickWobble / QuickRotate / QuickShow /
## QuickMousePlace / QuickFlyTo / QuickReparent / QuickTweenFloat）按树序取同类型第一个
## （含同播组一层内的成员）。
func _cache_quick_nodes() -> void:
	if show == null or not is_instance_valid(show):
		show = _first_performance_of(QuickShow) as QuickShow
	if mouse_place == null or not is_instance_valid(mouse_place):
		mouse_place = _first_performance_of(QuickMousePlace) as QuickMousePlace
	if pop_in == null or not is_instance_valid(pop_in):
		pop_in = _first_performance_of(QuickPopIn) as QuickPopIn
	if pop_out == null or not is_instance_valid(pop_out):
		pop_out = _first_performance_of(QuickPopOut) as QuickPopOut
	if zoom == null or not is_instance_valid(zoom):
		zoom = _first_performance_of(QuickZoom) as QuickZoom
	if wobble == null or not is_instance_valid(wobble):
		wobble = _first_performance_of(QuickWobble) as QuickWobble
	if rotate == null or not is_instance_valid(rotate):
		rotate = _first_performance_of(QuickRotate) as QuickRotate
	if fly_to == null or not is_instance_valid(fly_to):
		fly_to = _first_performance_of(QuickFlyTo) as QuickFlyTo
	if reparent == null or not is_instance_valid(reparent):
		reparent = _first_performance_of(QuickReparent) as QuickReparent
	if tween_float == null or not is_instance_valid(tween_float):
		tween_float = _first_performance_of(QuickTweenFloat) as QuickTweenFloat


## 按树序取同类型演出节点第一个（扫描范围与 [method get_performances] 一致）。
func _first_performance_of(script_type: Script) -> Node:
	for node in _collect_performance_nodes():
		if is_instance_of(node, script_type):
			return node
	return null


## 收集宿主名下全部演出节点（树序扁平）：直接子节点中实现播放契约者，
## 及同播组一层内的演出子节点；更深的嵌套属编排错误（播放期警告）不收录。
func _collect_performance_nodes() -> Array:
	var result: Array = []
	for child in get_children():
		if child is QuickParallel:
			for member in child.get_children():
				if member is QuickParallel:
					continue
				if _is_step_node(member):
					result.append(member)
		elif _is_step_node(child):
			result.append(child)
	return result


func _performance_base_name(kind: PerformanceKind) -> String:
	match kind:
		PerformanceKind.POP_IN:
			return "QuickPopIn"
		PerformanceKind.POP_OUT:
			return "QuickPopOut"
		PerformanceKind.ZOOM:
			return "QuickZoom"
		PerformanceKind.WOBBLE:
			return "QuickWobble"
		PerformanceKind.ROTATE:
			return "QuickRotate"
		PerformanceKind.MASK:
			return "QuickMask"
		PerformanceKind.SHOW:
			return "QuickShow"
		PerformanceKind.PLACE:
			return "QuickMousePlace"
		PerformanceKind.FLY_TO:
			return "QuickFlyTo"
		PerformanceKind.REPARENT:
			return "QuickReparent"
		PerformanceKind.TWEEN_FLOAT:
			return "QuickTweenFloat"
		PerformanceKind.PARALLEL:
			return "QuickParallel"
		PerformanceKind.DELAY:
			return "QuickDelay"
	return "Performance"


## 演出子节点唯一命名：首个用类型基名，其后追加 _2、_3…（仅保证唯一，不承载语义）。
func _unique_performance_name(base: String) -> String:
	if get_node_or_null(base) == null:
		return base
	var index := 2
	while get_node_or_null("%s_%d" % [base, index]) != null:
		index += 1
	return "%s_%d" % [base, index]



func _add_pop_in_performance() -> void:
	add_performance(PerformanceKind.POP_IN)


func _add_pop_out_performance() -> void:
	add_performance(PerformanceKind.POP_OUT)


func _add_zoom_performance() -> void:
	add_performance(PerformanceKind.ZOOM)


func _add_wobble_performance() -> void:
	add_performance(PerformanceKind.WOBBLE)


func _add_rotate_performance() -> void:
	add_performance(PerformanceKind.ROTATE)


func _add_mask_performance() -> void:
	add_performance(PerformanceKind.MASK)


func _add_show_performance() -> void:
	add_performance(PerformanceKind.SHOW)


func _add_place_performance() -> void:
	add_performance(PerformanceKind.PLACE)


func _add_fly_to_performance() -> void:
	add_performance(PerformanceKind.FLY_TO)


func _add_reparent_performance() -> void:
	add_performance(PerformanceKind.REPARENT)


func _add_tween_float_performance() -> void:
	add_performance(PerformanceKind.TWEEN_FLOAT)


func _add_parallel_performance() -> void:
	add_performance(PerformanceKind.PARALLEL)


func _add_delay_performance() -> void:
	add_performance(PerformanceKind.DELAY)


# ---------- 播放方式接线 ----------

## 接上按钮的按下信号（幂等）：_ready 恢复烘焙引用，setter 处理运行时换绑。
func _connect_play_button() -> void:
	if play_button == null:
		return
	if not play_button.pressed.is_connected(play):
		play_button.pressed.connect(play)


## 断开按钮的按下信号：换绑与退出树时调用（调用方保留对按钮的所有权）。
func _disconnect_play_button() -> void:
	if play_button == null:
		return
	if play_button.pressed.is_connected(play):
		play_button.pressed.disconnect(play)


#region 编辑器单趟预览

var _preview := AnimationPreview.new()


## 仅在编辑器播放一趟树序演出：开启全部演出子节点的宿主预览会话（解锁编辑器
## 隔离与完成信号、铺垫起播前置态），按树序播放一趟，结束后恢复编辑状态；再次
## 点击从原编辑状态重新开始。运行时调用无副作用。
func preview_play() -> void:
	if not Engine.is_editor_hint():
		return
	preview_stop()
	_stop_child_previews()
	var target := _resolve_ui()
	if target == null:
		push_warning("QuickUiAnimHost：目标控件缺失（ui 未导出且父节点不是 Control），无法预览树序演出。")
		return
	var properties: Array[StringName] = []
	properties.append_array(AnimationPreview.PRESENTATION_PROPERTIES)
	properties.append_array(AnimationPreview.GEOMETRY_PROPERTIES)
	if not _preview.begin(target, properties, false):
		return
	for node in _collect_performance_nodes():
		_capture_performance_state(node)
	_preview_run(_preview.generation)


func is_previewing() -> bool:
	return _preview.is_active()


## 停止并恢复：作废进行中的树序播放（剩余步骤不再播放）、结束全部演出子节点的
## 预览会话（杀动画、归还演出租约），再按两阶段恢复快照。保存前和退出树同步调用。
func preview_stop() -> void:
	if not is_previewing():
		return
	_cancel_tree_playback()
	for node in _collect_performance_nodes():
		if node.has_method("_end_host_preview_session"):
			node.call("_end_host_preview_session")
	_preview.stop()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		preview_stop()


## 子级演出组件自身的单次预览与宿主预览互斥——同一目标 ui 的快照恢复会互相覆盖。
func _stop_child_previews() -> void:
	for node in _collect_performance_nodes():
		if node.has_method("preview_stop"):
			node.call("preview_stop")


## 快照演出子节点的内部持久状态（authored 值随预览回滚）；QuickPopIn / QuickPopOut /
## QuickWobble / QuickRotate 的可回滚状态都在目标控件表现属性里、QuickDelay 无持久状态，均不在其列。
func _capture_performance_state(node: Node) -> void:
	if node is QuickZoom:
		_preview.capture(node, [&"_authored_mouse_filter"])
	elif node is QuickMask:
		_preview.capture(node, [&"progress"])
	elif node is QuickTweenFloat:
		_capture_tween_float_state(node)


## QuickTweenFloat 驱动的属性在目标脚本的导出面上，采集到其目标控件以便预览结束恢复
## authored 值；目标缺失或属性名留空时跳过。
func _capture_tween_float_state(node: QuickTweenFloat) -> void:
	var driven := node.resolve_target()
	if driven == null or node.property_name.is_empty():
		return
	var captured: Array[StringName] = [StringName(node.property_name)]
	_preview.capture(driven, captured)


func _preview_run(token: int) -> void:
	# 等当前布局帧完成；停止或重播后旧轮不能再初始化。
	await get_tree().process_frame
	if not _preview.is_current(token) or not is_inside_tree():
		return
	# 开启全部演出子节点的宿主预览会话，随后播放一趟树序（预览会话期间放行）。
	for node in _collect_performance_nodes():
		if node.has_method("_begin_host_preview_session"):
			node.call("_begin_host_preview_session")
	var done: Array = [false]
	finished.connect(
		func(_interrupted: bool): done[0] = true, CONNECT_ONE_SHOT)
	play()
	await _wait_preview_flag(done, token, _preview_total_bound())
	if _preview.is_current(token):
		preview_stop()


## 有界等待整树完成标志：逐帧检查；停止或重播（token 失效）返回 false，超时同样
## 返回 false 由调用方停止并恢复。
func _wait_preview_flag(done: Array, token: int, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not done[0]:
		if not _preview.is_current(token) or not is_inside_tree():
			return false
		if Time.get_ticks_msec() >= deadline:
			push_warning("QuickUiAnimHost：整树预览等待超时，已停止并恢复。")
			return false
		await get_tree().process_frame
	return true


## 整树预览的等待上界：全部演出步骤的有界等待之和加余量。
func _preview_total_bound() -> float:
	var total := 2.0
	for node in _collect_performance_nodes():
		total += _step_wait_timeout(node)
	return total

#endregion
