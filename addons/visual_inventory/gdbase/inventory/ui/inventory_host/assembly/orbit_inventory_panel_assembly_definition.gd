@tool
class_name OrbitInventoryPanelAssemblyDefinition
extends FreeInventoryPanelAssemblyDefinition
## ORBIT 轨道旋转面板的具体装配定义。
## 继承 FREE 抽象形式层的实例格面板、数据响应、命中与独立实例输入语义，
## 额外创建并拥有 OrbitTrack：实例格出生即挂在轨道节点名下，
## 由轨道均匀排布、整体自转并反向旋转保持图标直立。
## 轨道节点位于 Host 装配内部，场景作者无需预建 sibling 节点或填写 NodePath。
## 轨道的拨盘拖动与发牌动画参数在此 1:1 透传（同名同默认），
## Host 持有方经 get_assembly_part(OrbitTrack) 可随时调 play_deal_animation()。
## 实例格底板由 cell_style／show_cell_background 配置，经 FreeItemsPanel 下发。

## 实例格底板样式；空值表示透明底板。标准预设显式引用默认 StyleBoxTexture。
@export var cell_style: StyleBox
## 是否绘制实例格底板；关闭后仍保留布局、命中与物品显示。
@export var show_cell_background := true

@export var orbit_radius: float = 160.0
@export var rotation_speed: float = 0.5
@export var slot_start_angle: float = -PI / 2.0
@export var auto_spin: bool = true

@export_group("拨盘拖动")
## 是否启用鼠标拨盘拖动：按住后轨道跟随指针绕环心旋转，松手后可选回正。
@export var rotary_drag_enabled: bool = false
## 用于拨盘的鼠标按键。
@export var rotary_mouse_button: MouseButton = MOUSE_BUTTON_LEFT
## 指针距环心小于该半径（像素）时按下才开始拨动；拨动开始后不再受半径限制。
@export var rotary_grab_radius_pixels: float = 240.0
## 环心盲区半径（像素）：距环心小于该值的按压不起拨（固定中心帽）。
@export var rotary_hub_radius_pixels: float = 40.0
## 松开鼠标后是否用补间转回开始拖动时的角度。
@export var snap_back_on_release: bool = false
## 回正补间基准时长（秒）：按角距比例换算时，每 π 弧度角距耗时此值。
@export var snap_back_duration_seconds: float = 0.7
## 为 true 时回正恒定使用基准时长，不随角距伸缩。
@export var snap_back_fixed_duration: bool = false
## 回正死区（度）：松手时与回正目标的角距小于该值则不再补间。
@export_range(0, 360) var snap_back_dead_zone_degrees: float = 15.0

@export_group("发牌动画")
## 子控件生成时自动播放一轮发牌（轨道生成或实例格首次生成，帧末起播，
## 每生命周期一次）。
@export var deal_auto_play: bool = true
## 运行时新实例格加入轨道时是否自动播放该格子的入场动画（从环心飞到槽位）。
@export var entrance_on_child_added: bool = false
## 单个格子从环心飞到槽位的时长（秒）。
@export_range(0.05, 3.0, 0.01) var deal_duration_seconds: float = 0.35
## 相邻格子起播间隔（秒）；仅错峰起播模式生效，0 等效齐发。
@export_range(0.0, 2.0, 0.01) var deal_stagger_seconds: float = 0.12
## 起播模式：错峰（默认）或齐发。
@export var deal_launch_mode: OrbitTrack.DealLaunchMode = OrbitTrack.DealLaunchMode.STAGGERED
## 飞行过渡类型（默认 BACK 配 EASE_OUT，落位带一点过冲回弹）。
@export var deal_transition: Tween.TransitionType = Tween.TRANS_BACK
## 飞行缓动类型。
@export var deal_ease: Tween.EaseType = Tween.EASE_OUT


func _create_layout_nodes(
	assembly: InventoryPanelAssembly,
	context: InventoryPanelAssemblyContext
) -> bool:
	if not super(assembly, context):
		return false
	var track := OrbitTrack.new()
	track.name = "OrbitTrack"
	context.mount_owned_node(assembly, track)
	track.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	assembly.register_part(OrbitTrack, track)
	return true


func _recover_layout_nodes(
	assembly: InventoryPanelAssembly,
	context: InventoryPanelAssemblyContext
) -> bool:
	if not super(assembly, context):
		return false
	var track := context.host.get_node_or_null("OrbitTrack") as OrbitTrack
	if track == null:
		return false
	assembly.add_owned_node(track)
	assembly.register_part(OrbitTrack, track)
	# cell_parent 不随场景序列化：恢复时立即重建实例格挂载接缝，
	# 使恢复结果通过 validate 的完整装配校验（数据绑定随后由 refresh 下发）。
	(assembly.get_part(FreeItemsPanel) as FreeItemsPanel).cell_parent = track
	return true


func _apply_layout_configuration(
	assembly: InventoryPanelAssembly,
	panel: FreeItemsPanel,
	_context: InventoryPanelAssemblyContext
) -> void:
	var track := assembly.get_part(OrbitTrack) as OrbitTrack
	if track == null:
		return
	# 先下发实例格底板样式，再绑定轨道与挂载接缝。
	panel.configure_cell_presentation(cell_style, show_cell_background)
	track.rotary_drag_filter = panel.can_begin_layout_drag
	track.orbit_radius = orbit_radius
	track.rotation_speed = rotation_speed
	track.slot_start_angle = slot_start_angle
	track.auto_spin = auto_spin
	track.deal_auto_play = deal_auto_play
	track.entrance_on_child_added = entrance_on_child_added
	track.rotary_drag_enabled = rotary_drag_enabled
	track.rotary_mouse_button = rotary_mouse_button
	track.rotary_grab_radius_pixels = rotary_grab_radius_pixels
	track.rotary_hub_radius_pixels = rotary_hub_radius_pixels
	track.snap_back_on_release = snap_back_on_release
	track.snap_back_duration_seconds = snap_back_duration_seconds
	track.snap_back_fixed_duration = snap_back_fixed_duration
	track.snap_back_dead_zone_degrees = snap_back_dead_zone_degrees
	track.deal_duration_seconds = deal_duration_seconds
	track.deal_stagger_seconds = deal_stagger_seconds
	track.deal_launch_mode = deal_launch_mode
	track.deal_transition = deal_transition
	track.deal_ease = deal_ease
	panel.cell_parent = track


func _is_layout_valid(
	assembly: InventoryPanelAssembly,
	_context: InventoryPanelAssemblyContext
) -> bool:
	var track := assembly.get_part(OrbitTrack) as OrbitTrack
	if track == null:
		return false
	var panel := assembly.get_part(FreeItemsPanel) as FreeItemsPanel
	return panel != null and panel.cell_parent == track


func _get_layout_preferred_size(panel: FreeItemsPanel) -> Vector2:
	var max_cell_extent := 0.0
	for cell in panel.get_cells():
		if is_instance_valid(cell):
			max_cell_extent = maxf(max_cell_extent, maxf(cell.size.x, cell.size.y))
	return Vector2.ONE * (orbit_radius * 2.0 + max_cell_extent)


func teardown_assembly(assembly: InventoryPanelAssembly) -> void:
	# 先停止轨道处理，再走通用 teardown：格子挂在轨道名下，轨道节点释放时
	# 其子树格子一并释放，实例格面板的 PREDELETE 兜底清理其余外部格子。
	var track: OrbitTrack = null
	if assembly != null:
		track = assembly.get_part(OrbitTrack) as OrbitTrack
	if track != null:
		track.rotary_drag_filter = Callable()
		track.auto_spin = false
	super(assembly)
