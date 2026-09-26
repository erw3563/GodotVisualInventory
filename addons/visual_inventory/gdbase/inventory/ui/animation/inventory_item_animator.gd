class_name InventoryItemAnimator
extends Node
## 库存飞行表现由 InventorySceneServices 创建并持有，同一服务容器的 Host 共用。
## 订阅 InventoryHostTransferCenter.item_transferred，使用提交前源矩形快照解析落点并播放飞行图标。
## 特殊获得由调用方在实际入库后调用 play_gain，播放登场和飞入背包的视觉反馈。
## 动画在业务提交完成后执行，面板与实例显示位置通过服务层宿主注册表查询。

## 转移动画开始（幽灵起飞）时发出。
signal transfer_animation_started(item: ItemInstanceData)
## 转移动画结束（幽灵融入落点并释放）时发出。
signal transfer_animation_finished(item: ItemInstanceData)
## 特殊获得动画开始（幽灵在屏幕中心登场）时发出。
signal gain_animation_started(item: ItemInstanceData)
## 特殊获得动画结束（幽灵融入落点并释放）时发出。
signal gain_animation_finished(item: ItemInstanceData)

## 幽灵格渲染层级（与手持物品视图同层，高于普通背包面板）。
const GHOST_Z_INDEX := 100
## 尾段渐隐占整段飞行的比例。
const FADE_TAIL_RATIO := 0.35
## 获得动画目标格图标延迟的额外容差（登场前后各两帧布局稳定 + 落点解析两帧）。
const GAIN_ICON_REVEAL_MARGIN := 0.1

#region 演出参数
## 单次飞行时长（秒）。
@export_range(0.05, 2.0, 0.01) var animation_duration: float = 0.32
## 飞行缓动曲线。
@export var animation_transition: Tween.TransitionType = Tween.TRANS_CUBIC
## 飞行缓动方向。
@export var animation_ease: Tween.EaseType = Tween.EASE_OUT
## 飞行中段的峰值缩放（1.0 为不缩放）。
@export_range(1.0, 2.0, 0.01) var flight_peak_scale: float = 1.15
## 为 true 时飞行尾段渐隐，使幽灵融入落点处的真实物品格。
@export var fade_during_flight: bool = true
## 获得动画登场时长（秒）：缩放展开与晃动归正同播。
@export_range(0.05, 2.0, 0.01) var entrance_duration: float = 0.25
## 获得动画登场缓动曲线（默认带回弹）。
@export var entrance_transition: Tween.TransitionType = Tween.TRANS_BACK
## 获得动画登场缓动方向。
@export var entrance_ease: Tween.EaseType = Tween.EASE_OUT
## 获得动画登场晃动幅度角（度，负为逆时针；0 为不旋转）——晃动途经该角后归零。
@export_range(-360.0, 360.0, 0.1, "degrees") var entrance_start_rotation_degrees: float = -25.0
## 获得动画幽灵格子尺寸兜底（目标面板取不到格子尺寸时使用）。
@export var gain_ghost_cell_size: Vector2 = Vector2(48, 48)
#endregion

## 已订阅的转移中心（退出场景树时统一断开）。
var _subscribed_centers: Array[InventoryHostTransferCenter] = []
## 包含等待布局和飞行中的展示租约；退出时统一释放。
var _icon_display_releases: Array[Callable] = []


func _ready() -> void:
	_subscribe_existing_transfer_centers()
	get_tree().node_added.connect(_on_tree_node_added)


func _exit_tree() -> void:
	for release in _icon_display_releases.duplicate():
		_release_transfer_icon(release)
	var tree := get_tree()
	if tree != null and tree.node_added.is_connected(_on_tree_node_added):
		tree.node_added.disconnect(_on_tree_node_added)
	for center in _subscribed_centers:
		if is_instance_valid(center) and center.item_transferred.is_connected(_on_transfer_center_item_transferred):
			center.item_transferred.disconnect(_on_transfer_center_item_transferred)
	_subscribed_centers.clear()


#region 转移中心订阅
## 订阅场景中已存在的全部转移中心（含商店子类）。
func _subscribe_existing_transfer_centers() -> void:
	if !is_inside_tree():
		return
	var centers: Array[InventoryHostTransferCenter] = []
	_collect_transfer_centers(get_tree().root, centers)
	for center in centers:
		_connect_transfer_center(center)


## 递归收集节点子树中的全部转移中心。
func _collect_transfer_centers(node: Node, centers: Array[InventoryHostTransferCenter]) -> void:
	for child in node.get_children():
		if child is InventoryHostTransferCenter:
			var center := child as InventoryHostTransferCenter
			centers.append(center)
		_collect_transfer_centers(child, centers)


## 之后进树的转移中心（如战斗中动态装配的面板）经场景树节点新增信号兜住。
func _on_tree_node_added(node: Node) -> void:
	if node is InventoryHostTransferCenter:
		_connect_transfer_center(node)


## 连接单个转移中心（重复连接防护）。
func _connect_transfer_center(center: InventoryHostTransferCenter) -> void:
	if !is_instance_valid(center):
		return
	if center.item_transferred.is_connected(_on_transfer_center_item_transferred):
		return
	center.item_transferred.connect(_on_transfer_center_item_transferred)
	_subscribed_centers.append(center)
#endregion


#region 转移动画
## 收到转移成功信号：物品已在对侧背包——源矩形取信号载荷中的提交前活格快照，
## 等待布局稳定后解析落点并播放飞行（异步协程，不阻塞转移调用栈）。
func _on_transfer_center_item_transferred(
	item_instance: ItemInstanceData,
	_from_inventory: InventoryData,
	to_inventory: InventoryData,
	from_screen_rect: Rect2,
	item_num: int
) -> void:
	_play_transfer(item_instance, to_inventory, from_screen_rect, item_num)


func _play_transfer(
	item_instance: ItemInstanceData,
	to_inventory: InventoryData,
	source_rect: Rect2,
	item_num: int
) -> void:
	var services = _get_scene_services()
	if services == null:
		return
	# 空矩形表示源面板不可解析（如目录面板、面板不在树），静默跳过。
	if source_rect == Rect2():
		return
	var display_snapshot := _capture_display_snapshot(item_instance)
	# 必须在首次 await 前同步隐藏，布局等待期间不允许目标图标闪现。
	var release: Callable = services.acquire_item_icon_display_hold(to_inventory, item_instance)
	if release.is_valid():
		_icon_display_releases.append(release)
	var cleanup := _release_transfer_icon.bind(release)
	var target_rect: Rect2 = await _resolve_target_rect(services, to_inventory, item_instance)
	if target_rect == Rect2():
		cleanup.call()
		return
	var captured_rect: Rect2i = display_snapshot.get("rotated_rect", item_instance.get_rotated_shape_rect())
	var cell_size := source_rect.size / Vector2(captured_rect.size)
	play_flight(item_instance, item_num, cell_size, source_rect, target_rect, cleanup, display_snapshot)


## 完成、跳过、幽灵移除和动画节点退出均走幂等释放。
func _release_transfer_icon(release: Callable) -> void:
	if not _icon_display_releases.has(release):
		return
	_icon_display_releases.erase(release)
	if release.is_valid():
		release.call()


## 目标格盒子由面板在 item_added 信号内创建、位置延迟一帧设置，等布局稳定再解析；
## 物品被合并吸收（不在目标注册表）时退而取同种数据的幸存堆。
func _resolve_target_rect(services, to_inventory: InventoryData, item_instance: ItemInstanceData) -> Rect2:
	var tree := get_tree()
	if tree == null:
		return Rect2()
	await tree.process_frame
	await tree.process_frame
	if !is_instance_valid(item_instance) or !is_inside_tree() or !is_instance_valid(services):
		return Rect2()
	var target_rect: Rect2 = services.find_item_screen_rect(to_inventory, item_instance)
	if target_rect != Rect2():
		return target_rect
	return services.find_same_item_screen_rect(to_inventory, item_instance)


## 播放一次飞行演出：幽灵格从 source_rect 中心直线飞向 target_rect 中心，
## 途中缩放脉冲、尾段渐隐；参数矩形无效或物品失效时静默跳过。
## 公开供测试直接驱动纯矩形飞行；生产路径一律经信号订阅触发。
func play_flight(
	item_instance: ItemInstanceData,
	display_num: int,
	cell_size: Vector2,
	source_rect: Rect2,
	target_rect: Rect2,
	cleanup: Callable = Callable(),
	display_snapshot: Dictionary = {}
) -> void:
	if !is_instance_valid(item_instance) or source_rect == Rect2() or target_rect == Rect2():
		if cleanup.is_valid():
			cleanup.call()
		return
	if cell_size.x <= 0.0 or cell_size.y <= 0.0:
		cell_size = source_rect.size / Vector2(item_instance.get_rotated_shape_rect().size)
	var ghost := _spawn_ghost(item_instance, display_num, cell_size, display_snapshot)
	if cleanup.is_valid():
		ghost.tree_exiting.connect(cleanup, CONNECT_ONE_SHOT)
	var source_center := source_rect.get_center()
	var target_center := target_rect.get_center()
	ghost.global_position = source_center - ghost.size / 2.0
	transfer_animation_started.emit(item_instance)
	_fly_ghost(ghost, item_instance, source_center, target_center, transfer_animation_finished, cleanup)


## 驱动幽灵从 source_center 直线飞向 target_center：缓动插值、缩放脉冲、尾段渐隐；
## 结束释放幽灵并发出指定结束信号。飞行只写位置与 modulate，与登场缩放/旋转同帧可并存。
func _fly_ghost(ghost: InventoryItemBox, item_instance: ItemInstanceData, source_center: Vector2, target_center: Vector2, finished_signal: Signal, cleanup: Callable = Callable()) -> void:
	var tween := ghost.create_tween()
	tween.set_trans(animation_transition)
	tween.set_ease(animation_ease)
	tween.tween_method(
		_apply_flight_progress.bind(ghost, source_center, target_center),
		0.0, 1.0, animation_duration
	)
	if fade_during_flight:
		tween.parallel().tween_property(
			ghost, "modulate:a", 0.0, animation_duration * FADE_TAIL_RATIO
		).set_delay(animation_duration * (1.0 - FADE_TAIL_RATIO))
	tween.finished.connect(_on_flight_finished.bind(ghost, item_instance, finished_signal, cleanup))


## 单一进度驱动：位置插值与缩放脉冲（正弦峰）共用一个时间轴，保证同步。
func _apply_flight_progress(progress: float, ghost: Control, source_center: Vector2, target_center: Vector2) -> void:
	if !is_instance_valid(ghost):
		return
	var clamped_progress := clampf(progress, 0.0, 1.0)
	ghost.global_position = source_center.lerp(target_center, clamped_progress) - ghost.size / 2.0
	var pulse := 1.0 + (flight_peak_scale - 1.0) * sin(PI * clamped_progress)
	ghost.scale = Vector2.ONE * pulse


## 生成纯展示幽灵格（快照初始化，不连接物品信号）。
func _spawn_ghost(item_instance: ItemInstanceData, display_num: int, cell_size: Vector2, display_snapshot: Dictionary = {}) -> InventoryItemBox:
	var ghost := InventoryItemBox.new()
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ghost.z_index = GHOST_Z_INDEX
	add_child(ghost)
	ghost.init_cell_snapshot(item_instance, cell_size, cell_size, display_num,
		display_snapshot if not display_snapshot.is_empty() else _capture_display_snapshot(item_instance))
	ghost.pivot_offset = ghost.size / 2.0
	return ghost


## 一次飞行结束：释放幽灵并发出指定结束信号。
func _on_flight_finished(ghost: InventoryItemBox, item_instance: ItemInstanceData, finished_signal: Signal, cleanup: Callable = Callable()) -> void:
	if cleanup.is_valid():
		cleanup.call()
	if is_instance_valid(ghost):
		ghost.queue_free()
	if is_instance_valid(item_instance):
		finished_signal.emit(item_instance)
#endregion


#region 特殊获得动画（调用型）
## 特殊获得动画：幽灵物品格在屏幕中心经 Zoom+Rotate+渐显登场，随后飞向目标背包格。
## 由外界在物品实际入包后显式调用（如对话给予物品）；普通获得路径不调用本方法。
## 落点不可解析（目标面板不在树）时幽灵原地淡出退场，仍发结束信号。
func play_gain(item_instance: ItemInstanceData, display_num: int, target_inventory: InventoryData) -> void:
	if !is_instance_valid(item_instance) or target_inventory == null:
		return
	var services = _get_scene_services()
	if services == null:
		return
	# 目标格图标随幽灵抵达才显现：入包瞬间即延迟（登场 + 飞行 + 布局容差）；
	# 合并被吸收时无自有格子，方法自动不生效。
	services.delay_item_icon_display(
		target_inventory,
		item_instance,
		entrance_duration + animation_duration + GAIN_ICON_REVEAL_MARGIN
	)
	var ghost := _spawn_ghost(item_instance, display_num, _resolve_gain_cell_size(services, target_inventory))
	var screen_center := _get_screen_center()
	ghost.global_position = screen_center - ghost.size / 2.0
	gain_animation_started.emit(item_instance)
	await _play_center_entrance(ghost)
	if !is_instance_valid(ghost):
		return
	var target_rect: Rect2 = await _resolve_target_rect(services, target_inventory, item_instance)
	if target_rect == Rect2():
		_retreat_ghost_in_place(ghost, item_instance)
		return
	_fly_ghost(ghost, item_instance, screen_center, target_rect.get_center(), gain_animation_finished)


## 幽灵居中登场：起点隐藏且缩为 0；布局稳定后显形，缩放与旋转同播归正。
func _play_center_entrance(ghost: InventoryItemBox) -> void:
	ghost.scale = Vector2.ZERO
	ghost.rotation_degrees = entrance_start_rotation_degrees
	ghost.visible = false
	await _await_layout_settled(ghost)
	if !is_instance_valid(ghost):
		return
	ghost.pivot_offset = ghost.size * 0.5
	ghost.visible = true
	var tween := ghost.create_tween()
	tween.set_parallel(true)
	tween.set_trans(entrance_transition)
	tween.set_ease(entrance_ease)
	tween.tween_property(ghost, "scale", Vector2.ONE, entrance_duration)
	tween.tween_property(ghost, "rotation_degrees", 0.0, entrance_duration)
	await tween.finished


## 等两帧让容器与锚点布局稳定。
func _await_layout_settled(node: Node) -> void:
	if node == null or not node.is_inside_tree():
		return
	var tree := node.get_tree()
	await tree.process_frame
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	await tree.process_frame


## 视口可见矩形中心（本服务层 canvas 口径；层 transform 恒等时即屏幕中心）。
func _get_screen_center() -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return Vector2(480.0, 270.0)
	return viewport.get_visible_rect().get_center()


## 获得动画幽灵格子尺寸：优先目标库存宿主面板的格子尺寸，取不到用导出兜底。
func _resolve_gain_cell_size(services, target_inventory: InventoryData) -> Vector2:
	var host = services.find_inventory_host(target_inventory)
	if host != null:
		var grid_panel = host.get("grid_panel")
		if grid_panel != null and "cell_size" in grid_panel:
			return grid_panel.cell_size
		var free_panel = host.get("free_panel")
		if free_panel != null and free_panel.has_method("get_free_cell_size"):
			return free_panel.get_free_cell_size()
	return gain_ghost_cell_size


## 落点不可解析时幽灵原地淡出退场（仍发结束信号，保证调用方等待语义一致）。
func _retreat_ghost_in_place(ghost: InventoryItemBox, item_instance: ItemInstanceData) -> void:
	var tween := ghost.create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, entrance_duration)
	tween.finished.connect(_on_flight_finished.bind(ghost, item_instance, gain_animation_finished))
#endregion


## 当前是否有飞行演出正在进行（以幽灵格存在为准）。
func has_active_flight() -> bool:
	for child in get_children():
		if child is InventoryItemBox:
			return true
	return false


## 服务层经父节点鸭子获取（动画节点固定挂载于 InventorySceneServices 下；
## 不作类型引用，避免「服务层→动画节点→……→服务层」的类名环依赖）。
func _get_scene_services():
	var parent = get_parent()
	if parent != null and parent.has_method("find_item_screen_rect"):
		return parent
	return null


func _capture_display_snapshot(item: ItemInstanceData) -> Dictionary:
	var provider := SceneInventoryItemViewProvider.new(_get_scene_services())
	return {"texture": provider.capture_display_texture(item), "dir": item.dir,
		"local_rect": item.get_local_shape_rect(), "rotated_rect": item.get_rotated_shape_rect()}
