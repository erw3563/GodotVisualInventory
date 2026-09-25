@tool
class_name OrbitTrack
extends Control
## 通用环形排列节点：按直接 Control 子节点的顺序均匀排列，并支持整体自转。
## 管理子节点的位置、旋转与中心枢轴，不修改尺寸；子节点相对轨道保持直立。
## 隐藏的 Control 仍占槽位，非 Control 子节点不参与排列。
## 不依赖业务数据；调用方负责创建、挂载和释放自己的子节点。
## 可选拨盘拖动：在拨盘环带内（环心盲区与抓取半径之间）按住鼠标沿圆周拨动，
## 轨道像老式电话拨号盘一样跟随指针旋转（支持多圈），松手后可补间回正到拨动开始
## 的角度。环带内压在子控件上同样起拨，交互控件应布置在环带外。
## 可选发牌动画：play_deal_animation() 让全部子控件先隐藏并移到环心，
## 再按起播模式（错峰/齐发）依次或同时飞回各自槽位（播放前就隐藏的子控件
## 占位但不显形）。
## 单个子控件可单独入场：play_entrance_animation(control) 让该控件从环心飞到
## 当前槽位，不影响其它子控件；entrance_on_child_added 可让运行时新加入的
## 子控件自动播放入场。

## 发牌动画全部物品落位后发出（空轨道起播也立即发，等待语义一致）。
signal deal_finished

## 轨道半径（像素）。
@export var orbit_radius := 160.0
## 自转角速度（弧度/秒）。
@export var rotation_speed := 0.5
## 首槽位角度（默认 -90° 即环的正上方）。
@export var slot_start_angle := -PI / 2.0
## 是否持续自转；暂停后子控件停在当前角度。
@export var auto_spin := true:
	set(value):
		auto_spin = value
		if is_node_ready():
			_sync_processing()

@export_group("拨盘拖动")
## 是否启用鼠标拨盘拖动：按住后轨道跟随指针绕环心旋转，松手后可选回正。
@export var rotary_drag_enabled := false:
	set(value):
		rotary_drag_enabled = value
		if is_node_ready():
			if not rotary_drag_enabled:
				_cancel_rotary_interaction()
			_sync_processing()
## 触发拨盘拖动的鼠标按键。
@export var rotary_mouse_button: MouseButton = MOUSE_BUTTON_LEFT
## 指针距环心小于该半径（像素）时按下才开始拨动（含压在子控件上）；拨动开始后不再受半径限制。
@export var rotary_grab_radius_pixels := 240.0
## 环心盲区半径（像素）：距环心小于该值的按压不起拨——对应老式拨号盘固定的中心帽，
## 也避开环心处指针角不可靠的问题（交互控件可布置在盲区内）。
@export var rotary_hub_radius_pixels := 40.0
## 松手后是否补间转回拨动开始时的角度。
@export var snap_back_on_release := false
## 回正补间基准时长（秒）：按角距比例换算时，每 π 弧度角距耗时此值。
@export var snap_back_duration_seconds := 0.7
## 为 true 时回正恒定使用基准时长，不随角距伸缩。
@export var snap_back_fixed_duration := false
## 回正死区（度）：松手时与回正目标的角距小于该值则不再补间。
@export_range(0, 360) var snap_back_dead_zone_degrees := 15.0

@export_group("发牌动画")
## 发牌起播模式。
enum DealLaunchMode {
	## 按枚举序错峰起播：第 k 个子控件的起播时刻 = k × 错峰间隔。
	STAGGERED,
	## 齐发：全部子控件同时起飞（忽略错峰间隔），总时长 = 单飞时长。
	SIMULTANEOUS,
}

## 子控件生成时自动播放一轮发牌：进入树时已有子控件、或运行时首次有子控件加入
## 即在**帧末**起播（同一帧内批量加入的子控件全部计入起播数量、总时长与可见性
## 快照）；每个轨道生命周期只触发一次（后续增删不重播），编辑器内不触发。
@export var deal_auto_play: bool = true
## 运行时新子控件加入轨道时，是否自动播放该子控件的入场动画（从环心飞到当前
## 槽位，复用发牌的单飞时长与过渡，不影响其它子控件）。默认关；编辑器不触发；
## 整轨自动发牌尚未起播（含帧末延迟窗口）时由整轨发牌统一接管，不单独入场。
@export var entrance_on_child_added := false
## 单个子控件从环心飞到槽位的时长（秒）。
@export_range(0.05, 3.0, 0.01) var deal_duration_seconds := 0.35
## 相邻子控件起播间隔（秒）；仅错峰起播模式生效，0 等效齐发。
@export_range(0.0, 2.0, 0.01) var deal_stagger_seconds := 0.12
## 起播模式：错峰（默认）或齐发。
@export var deal_launch_mode: DealLaunchMode = DealLaunchMode.STAGGERED
## 飞行过渡类型（默认 BACK 配 EASE_OUT，落位带一点过冲回弹）。
@export var deal_transition: Tween.TransitionType = Tween.TRANS_BACK
## 飞行缓动类型。
@export var deal_ease: Tween.EaseType = Tween.EASE_OUT
## 编辑器检查器单次预览（同四面板先例）：播放一轮发牌动画，动画自恢复、
## 播完即正常排列；运行时入口无副作用，游戏内请用 play_deal_animation()。
@export_tool_button("播放一次", "Play") var preview_play_action: Callable = preview_play
@export_tool_button("停止并恢复", "Stop") var preview_stop_action: Callable = preview_stop

## 可选运行时起拨裁决，由组装方注入；未设置时保持通用拨盘语义。
## 参数为视口坐标的按键事件，轨道不认识库存或其它业务对象。
var rotary_drag_filter: Callable

var _rotary_dragging := false
var _rotary_pointer_angle := 0.0
var _rotary_rest_rotation := 0.0
var _snap_back_tween: Tween
var _deal_playing := false
var _deal_clock := 0.0
var _deal_total := 0.0
var _deal_spawn_played := false
## 帧末延迟起播的自动发牌是否已排队（防同帧批量加入时重复排队）。
var _spawn_deal_deferred := false
## 起播时的可见性快照（控件实例 → 是否可见）：播放前就被隐藏的子控件全程保持
## 隐藏但仍参与槽位重算（隐藏占位语义）；播放中加入的子控件不在快照里，按可见处理。
var _deal_visibility_snapshot := {}
## 进行中的单控件入场飞行，元素为 [Control, 已飞行秒]；整轨发牌重播与强制收尾时清空。
var _entrance_flights: Array = []
## 已见过的子控件实例 id 集合：识别"运行时新加入"的子控件（进入树时已有的不算新加入）。
var _seen_child_instance_ids := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	pivot_offset = size * 0.5
	if !resized.is_connected(_on_resized):
		resized.connect(_on_resized)
	_remember_current_children()
	_sync_processing()
	_try_auto_play_spawn_deal()


func _process(delta: float) -> void:
	if _deal_playing:
		_deal_clock += delta
		if _deal_clock >= _deal_total:
			_finish_deal()
	_advance_entrance_flights(delta)
	if auto_spin and not Engine.is_editor_hint() and not _rotary_dragging \
			and not _is_snapping_back():
		rotation += rotation_speed * delta
	relayout_slots()


## 拨盘输入统一走 _input（GUI 处理之前，不可被消费拦截）：抓取半径内的按压即刻
## 起拨——默认压在卡片或子控件上也可抓住拨盘；组合交互由 rotary_drag_filter 裁决；
## 跟手与松手同样在 GUI 之前，指针扫过会消费鼠标事件的控件不中断、释放被消费不卡死。
## 全程使用事件自身坐标（派发时已换算到本画布空间），不读视口鼠标位。
func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	var button_event := event as InputEventMouseButton
	if button_event != null and button_event.button_index == rotary_mouse_button:
		if button_event.pressed:
			_try_begin_rotary_drag(button_event)
		elif _rotary_dragging:
			_end_rotary_drag()
		return
	if not _rotary_dragging:
		return
	var motion_event := event as InputEventMouseMotion
	if motion_event != null:
		_track_rotary_pointer(_canvas_position(motion_event.position))


## 按压起拨判定：启用、可见、未在拨动且指针落在拨盘环带内（盲区 < 距环心 ≤ 抓取半径）。
func _try_begin_rotary_drag(button_event: InputEventMouseButton) -> void:
	if Engine.is_editor_hint():
		return
	if not rotary_drag_enabled or not is_visible_in_tree() or _rotary_dragging:
		return
	if rotary_drag_filter.is_valid() and not rotary_drag_filter.call(button_event):
		return
	var to_center := _canvas_position(button_event.position) - get_track_center_global()
	var center_distance := to_center.length()
	if center_distance > rotary_grab_radius_pixels or center_distance < rotary_hub_radius_pixels:
		return
	_begin_rotary_drag(to_center.angle())


## 当前是否处于拨盘拖动中（按住跟手阶段，不含回正补间）。
func is_rotary_dragging() -> bool:
	return _rotary_dragging


## 播放发牌动画：全部子控件先隐藏并移到环心，再按起播模式（错峰/齐发）飞回
## 各自槽位；槽位按当前全部子控件（含隐藏者）重算。播放中重播从头再来，且沿用
## 首次起播时的可见性快照——不把动画自身隐藏的卡片误判为本来就隐藏。
func play_deal_animation() -> void:
	var orbit_controls := get_orbit_controls()
	if orbit_controls.is_empty():
		deal_finished.emit()
		return
	# 整轨发牌接管全部子控件：进行中的单控件入场一并终止。
	_entrance_flights.clear()
	if not _deal_playing:
		_deal_visibility_snapshot.clear()
		for control in orbit_controls:
			_deal_visibility_snapshot[control] = control.visible
	for control in orbit_controls:
		control.visible = false
	_deal_playing = true
	_deal_clock = 0.0
	_deal_total = deal_duration_seconds
	if deal_launch_mode == DealLaunchMode.STAGGERED:
		_deal_total += deal_stagger_seconds * float(orbit_controls.size() - 1)
	relayout_slots()
	_sync_processing()


## 发牌动画是否正在播放。
func is_deal_playing() -> bool:
	return _deal_playing


## 播放单个子控件的入场动画：该控件从环心飞到当前槽位，复用发牌的单飞时长与
## 过渡（槽位随自转/拨盘每帧重算，飞行追着活动目标收敛）；不影响其它子控件的
## 位置与可见性。目标不是本轨道的直接 Control 子节点时告警忽略；目标本身隐藏
## 时不做任何事（隐藏占位语义，不显形）。正在进行整轨发牌时对其中某控件调用，
## 该控件改走入场飞行；整轨发牌重播会接管并终止所有入场飞行。
func play_entrance_animation(control: Control) -> void:
	if control == null or control.get_parent() != self:
		push_warning("OrbitTrack 入场动画：目标不是本轨道的直接子控件，已忽略。")
		return
	if not control.visible:
		return
	if is_entrance_playing(control):
		return
	_entrance_flights.append([control, 0.0])
	_sync_processing()


## 指定子控件是否正在播放入场动画。
func is_entrance_playing(control: Control) -> bool:
	return _entrance_elapsed_for(control) >= 0.0


## 编辑器单次预览：在编辑器内播放一轮发牌动画（播放中再点从头重播）；
## 运行时调用无副作用，游戏内请用 play_deal_animation()。
func preview_play() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if get_orbit_control_count() == 0:
		push_warning("OrbitTrack 预览：轨道上没有子控件，无事可播。")
		return
	play_deal_animation()


## 立即结束编辑器预览并恢复全部子控件到正常排列与可见性；空闲或运行时调用无副作用。
func preview_stop() -> void:
	if not Engine.is_editor_hint():
		return
	_force_finish_deal()
	_force_finish_entrances()


## 生成时自动发牌：运行时首次出现子控件后延迟到**帧末**起播——同一帧内批量加入
## 的子控件（如库存装配逐格挂载）到齐后再计算起播数量、总时长与可见性快照。
## 每个生命周期至多一次；关闭开关、编辑器环境或空轨道不触发。
func _try_auto_play_spawn_deal() -> void:
	if _deal_spawn_played or not deal_auto_play or Engine.is_editor_hint():
		return
	if not is_inside_tree() or get_orbit_control_count() == 0:
		return
	if _spawn_deal_deferred:
		return
	_spawn_deal_deferred = true
	call_deferred("_deferred_spawn_deal")


## 帧末执行的自动发牌：同帧批量加入的子控件此刻已全部在轨道上。
func _deferred_spawn_deal() -> void:
	_spawn_deal_deferred = false
	if _deal_spawn_played or not deal_auto_play or Engine.is_editor_hint():
		return
	if not is_inside_tree() or get_orbit_control_count() == 0:
		return
	_deal_spawn_played = true
	play_deal_animation()


## 识别运行时新加入的子控件并按配置起播其入场动画；同时清理已移除子控件的登记。
## 整轨自动发牌尚在待起播窗口（帧末延迟未执行）时跳过——首批子控件由整轨发牌
## 统一接管，不逐张入场。
func _sync_child_added_entrances() -> void:
	var current_instance_ids := {}
	for control in get_orbit_controls():
		var instance_id := control.get_instance_id()
		current_instance_ids[instance_id] = true
		if _seen_child_instance_ids.has(instance_id):
			continue
		_seen_child_instance_ids[instance_id] = true
		if _should_entrance_new_child():
			play_entrance_animation(control)
	for instance_id in _seen_child_instance_ids.keys():
		if not current_instance_ids.has(instance_id):
			_seen_child_instance_ids.erase(instance_id)


func _should_entrance_new_child() -> bool:
	if not entrance_on_child_added or Engine.is_editor_hint():
		return false
	if deal_auto_play and not _deal_spawn_played:
		return false
	return true


## 把当前子控件登记为已见：进入树时已存在的子控件不算"运行时新加入"，不触发育场。
func _remember_current_children() -> void:
	for control in get_orbit_controls():
		_seen_child_instance_ids[control.get_instance_id()] = true


## 立即完成进行中的发牌：跳到终点，可见性按快照恢复、位置回到正常排列。
func _force_finish_deal() -> void:
	if not _deal_playing:
		return
	_deal_clock = _deal_total
	_finish_deal()


## 环形轨道圆心（矩形中心）的全局坐标；旋转绕中心枢轴，圆心在旋转中保持不动。
func get_track_center_global() -> Vector2:
	return get_global_transform() * (size * 0.5)


func _notification(what: int) -> void:
	# 子节点增删（子控件加入 / 移除）时立即重排一次，并补挂新控件的尺寸监听，
	# 暂停自转期间也能保持均匀、响应控件尺寸变化。
	if what == NOTIFICATION_CHILD_ORDER_CHANGED:
		_ensure_control_resize_listeners()
		_sync_child_added_entrances()
		relayout_slots()
		_try_auto_play_spawn_deal()
	# 保存场景前终结进行中的发牌与入场，不把动画中间状态（隐藏/驻留环心）写入场景。
	elif what == NOTIFICATION_EDITOR_PRE_SAVE:
		_force_finish_deal()
		_force_finish_entrances()


func _exit_tree() -> void:
	# 退出树时立即终结进行中的发牌、入场与回正补间，子控件不留隐藏或半飞行状态。
	_force_finish_deal()
	_force_finish_entrances()
	_kill_snap_back_tween()
	_spawn_deal_deferred = false


## 把当前子控件的 resized 信号接到重排上：控件自身尺寸变化（非增删）时也重新收敛，
## 包括暂停自转期间。
func _ensure_control_resize_listeners() -> void:
	for control in get_orbit_controls():
		if not control.resized.is_connected(_on_control_resized):
			control.resized.connect(_on_control_resized)


func _on_control_resized() -> void:
	relayout_slots()


## 把当前子控件按枚举序 k/n 均匀摆上环形轨道，并反向旋转抵消自转（子控件保持直立）。
## 发牌播放期间：未轮到的隐藏驻留环心，轮到的从环心插值飞向**当前**槽位
## （槽位随自转/拨盘每帧重算，飞行追着活动目标收敛）。
func relayout_slots() -> void:
	var orbit_controls := get_orbit_controls()
	var slot_count := orbit_controls.size()
	if slot_count == 0:
		return
	var track_center := size * 0.5
	for slot_index in slot_count:
		var control := orbit_controls[slot_index]
		var angle := slot_start_angle + TAU * float(slot_index) / float(slot_count)
		var slot_center := track_center + Vector2(cos(angle), sin(angle)) * orbit_radius
		# 反向旋转必须绕控件中心，否则不同尺寸控件的实际显示中心会偏离轨道槽位。
		control.pivot_offset = control.size * 0.5
		control.rotation = -rotation
		if _entrance_elapsed_for(control) >= 0.0:
			_write_entrance_position(control, track_center, slot_center)
		elif _deal_playing:
			_write_deal_position(control, slot_index, track_center, slot_center)
		else:
			control.position = slot_center - control.size * 0.5


## 发牌中单个子控件的位置与可见性：未轮到的隐藏驻留环心；轮到的恢复显示
## （按起播时的快照——起播前就被使用者隐藏的保持隐藏、只占位）并按进度插值飞行。
func _write_deal_position(control: Control, slot_index: int, track_center: Vector2,
		slot_center: Vector2) -> void:
	var progress := _deal_progress_for(slot_index)
	if progress <= 0.0:
		control.visible = false
		control.position = track_center - control.size * 0.5
		return
	control.visible = _deal_visibility_snapshot.get(control, true)
	if progress >= 1.0:
		control.position = slot_center - control.size * 0.5
		return
	# 本引擎（4.8.dev）interpolate_value 六参签名第 4 参为插值开关：false 直接返回 to，
	# true 才按 trans/ease 计算缓动权重。
	var eased: float = Tween.interpolate_value(0.0, 1.0, progress, true, deal_transition, deal_ease)
	control.position = track_center.lerp(slot_center, eased) - control.size * 0.5


## 发牌子控件的飞行进度：起播时刻按模式取枚举序 × 错峰间隔（齐发恒为 0），
## 除以单飞时长。
func _deal_progress_for(slot_index: int) -> float:
	var launch_offset := 0.0
	if deal_launch_mode == DealLaunchMode.STAGGERED:
		launch_offset = deal_stagger_seconds * float(slot_index)
	return (_deal_clock - launch_offset) / deal_duration_seconds


## 入场飞行中单个子控件的位置：从环心按进度插值飞向当前槽位（槽位随自转/拨盘
## 每帧重算）；入场不改变可见性（隐藏控件不发起入场）。
func _write_entrance_position(control: Control, track_center: Vector2,
		slot_center: Vector2) -> void:
	var progress := _entrance_elapsed_for(control) / deal_duration_seconds
	if progress >= 1.0:
		control.position = slot_center - control.size * 0.5
		return
	var eased: float = Tween.interpolate_value(0.0, 1.0, progress, true,
		deal_transition, deal_ease)
	control.position = track_center.lerp(slot_center, eased) - control.size * 0.5


## 指定子控件的已飞行秒数；不在入场飞行中返回 -1。
func _entrance_elapsed_for(control: Control) -> float:
	for flight in _entrance_flights:
		if is_instance_valid(flight[0]) and flight[0] == control:
			return flight[1]
	return -1.0


## 推进入场飞行时钟：到时、已移除或已释放的控件结束入场，移交常规排布。
func _advance_entrance_flights(delta: float) -> void:
	if _entrance_flights.is_empty():
		return
	var surviving: Array = []
	for flight in _entrance_flights:
		# 先对 Variant 做有效性判定：typed 赋值为 Control 时，已释放实例会直接报错。
		var raw_flight_ref = flight[0]
		if not is_instance_valid(raw_flight_ref) or raw_flight_ref.get_parent() != self:
			continue
		var control: Control = raw_flight_ref
		var elapsed: float = flight[1] + delta
		if elapsed < deal_duration_seconds:
			surviving.append([control, elapsed])
	_entrance_flights = surviving
	if _entrance_flights.is_empty():
		_sync_processing()


## 立即结束全部入场飞行：位置回到常规槽位（保存场景/退出树前收尾用）。
func _force_finish_entrances() -> void:
	if _entrance_flights.is_empty():
		return
	_entrance_flights.clear()
	relayout_slots()
	_sync_processing()


func _finish_deal() -> void:
	_deal_playing = false
	# 强制收尾（预览停止/退出树）时部分子控件可能尚未轮到起播，仍处隐藏态；
	# 统一按起播快照恢复可见性后再清空，正常播完时此循环是幂等的。
	for control in get_orbit_controls():
		control.visible = _deal_visibility_snapshot.get(control, true)
	_deal_visibility_snapshot.clear()
	relayout_slots()
	_sync_processing()
	deal_finished.emit()


## 当前直接 Control 子节点，按场景树顺序返回。排除已 queue_free 等待释放的节点：
## 全量重建的旧格子临死前一帧不再占位，避免把幽灵格子计入排布、发牌起播数量与总时长。
func get_orbit_controls() -> Array[Control]:
	var orbit_controls: Array[Control] = []
	for child in get_children():
		var control := child as Control
		if control != null and is_instance_valid(control) \
				and not control.is_queued_for_deletion():
			orbit_controls.append(control)
	return orbit_controls


## 当前直接 Control 子节点数量。
func get_orbit_control_count() -> int:
	return get_orbit_controls().size()


## 运行时切换自转（暂停 / 继续）：状态只属于本节点，
## 不影响其它轨道实例。
func set_orbit_spinning(spinning: bool) -> void:
	auto_spin = spinning


func _on_resized() -> void:
	pivot_offset = size * 0.5
	relayout_slots()


## 视口坐标 → 本画布空间坐标。
func _canvas_position(viewport_position: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse() * viewport_position


func _begin_rotary_drag(pointer_angle: float) -> void:
	_kill_snap_back_tween()
	_rotary_dragging = true
	_rotary_rest_rotation = rotation
	_rotary_pointer_angle = pointer_angle
	_sync_processing()


func _end_rotary_drag() -> void:
	_rotary_dragging = false
	_start_snap_back_if_needed()
	_sync_processing()


## 拨动期间把指针绕环心的角增量累积到轨道旋转上：跟随指针、支持多圈。
func _track_rotary_pointer(pointer_canvas_position: Vector2) -> void:
	var pointer_angle := (pointer_canvas_position - get_track_center_global()).angle()
	rotation += angle_difference(_rotary_pointer_angle, pointer_angle)
	_rotary_pointer_angle = pointer_angle


## 松手后按配置补间回拨动开始时的角度。角距取原始差值而非最短路径，
## 多圈拨动会沿原路整圈退回，模拟老式拨号盘的回卷。
func _start_snap_back_if_needed() -> void:
	if not snap_back_on_release:
		return
	var angle_distance := absf(_rotary_rest_rotation - rotation)
	if snap_back_duration_seconds <= 0.0:
		rotation = _rotary_rest_rotation
		relayout_slots()
		return
	if angle_distance < deg_to_rad(snap_back_dead_zone_degrees):
		return
	var tween_time := snap_back_duration_seconds
	if not snap_back_fixed_duration:
		tween_time = snap_back_duration_seconds * angle_distance / PI
	_snap_back_tween = create_tween()
	_snap_back_tween.finished.connect(_on_snap_back_finished)
	_snap_back_tween.tween_property(self, "rotation", _rotary_rest_rotation, tween_time)


func _is_snapping_back() -> bool:
	return _snap_back_tween != null and is_instance_valid(_snap_back_tween)


func _on_snap_back_finished() -> void:
	_snap_back_tween = null
	_sync_processing()


func _kill_snap_back_tween() -> void:
	if _snap_back_tween != null and is_instance_valid(_snap_back_tween):
		_snap_back_tween.kill()
	_snap_back_tween = null


## 关闭拨盘时中断进行中的拨动与回正，不留悬挂状态。
func _cancel_rotary_interaction() -> void:
	_rotary_dragging = false
	_kill_snap_back_tween()


## 帧循环开关：自转、拨动、回正、发牌或任一入场飞行进行时保持 _process 运行，
## 其余交给通知重排。编辑器空闲态不自转不响应输入（同面板预览规范的编辑器隔离），
## 仅发牌预览与入场需要帧循环。
func _sync_processing() -> void:
	if Engine.is_editor_hint():
		set_process(_deal_playing or not _entrance_flights.is_empty())
		return
	set_process(auto_spin or _rotary_dragging or _is_snapping_back() \
		or _deal_playing or not _entrance_flights.is_empty())
