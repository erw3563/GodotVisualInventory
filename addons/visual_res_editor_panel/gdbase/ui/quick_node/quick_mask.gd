@tool
class_name QuickMask
extends TextureRect
## 快捷系演出件：纹理遮罩显隐——按灰度遮罩图案（内置 8 种或自定义 mask_texture）把
## 内容（纯色 [member tint] 或 [member content_texture]）在完全隐藏与完全显示之间演出。
## 单个节点只负责一个目标端：[member target_progress] 声明目标，统一播放契约
## [method play] 从当前 [member progress] 到达该目标，已处目标端时先把进度归位到另一
## 端点再起播，每轮演出都有完整行程（progress 是本件自有状态，归位由本件承担）；两个
## 目标端不同的实例分属两个宿主即表达显示与隐藏两条路径。装载铺场契约
## [method prepare_play] 把目标为完全显示的节点在装载时瞬时置为隐藏，弥合装载帧到
## 起播前的闪现。
## TextureRect 本身即视觉：设置 [member ui] 后遮罩矩形自动对齐并持续跟随目标控件
## （矩形耦合，只读目标矩形、只写自身 geometry），空引用时自呈现、摆位归作者；经
## QuickUiAnimHost.add_performance(PerformanceKind.MASK) 纳入树序时间线，也可散装摆放；
## 层级（绘制在目标之上）由作者负责。
## 编辑器内提供 Inspector「动画预览」单次演出（仅编辑器生效，机制见 ui/core AnimationPreview）；
## 编辑器空闲态 play 全隔离。
## 原始 shader 与图案：Copyright © 2021 GlassBrick，MIT 协议（见 texture_mask/LICENSE）。

## 到达自身目标端时发出；停止或替换播放不会发出。
signal play_finished

const MASK_SHADER = preload("texture_mask/texture_mask.gdshader")
## 内置的 8 种遮罩图案。
const PATTERNS: Dictionary = {

	"circle": preload("texture_mask/patterns/circle.png"),
	"curtains": preload("texture_mask/patterns/curtains.png"),
	"diagonal": preload("texture_mask/patterns/diagonal.png"),
	"horizontal": preload("texture_mask/patterns/horizontal.png"),
	"radial": preload("texture_mask/patterns/radial.png"),
	"scribbles": preload("texture_mask/patterns/scribbles.png"),
	"squares": preload("texture_mask/patterns/squares.png"),
	"vertical": preload("texture_mask/patterns/vertical.png"),
}

## 跟随的目标控件：设置后遮罩矩形（全局位置与尺寸）自动对齐并持续跟随——目标的矩形
## 变化信号即时对齐位移与尺寸，逐帧采样把目标自身的缩放、祖先变换与容器重排带进对齐；
## 设置时与每次起播前立即对齐一次，预览恢复后重新对齐；空引用时自呈现（摆位由作者
## 负责）。QuickUiAnimHost 生成时赋宿主目标，之后以烘焙引用为准。
## 目标与遮罩须在同一画布坐标系；遮罩父级须为普通 Control（容器会重排子节点）。
@export var ui: Control:
	set(value):
		_disconnect_ui_tracking()
		ui = value
		if is_node_ready():
			_connect_ui_tracking()

## 灰度遮罩纹理；留空时使用普通透明度渐变。
@export var mask_texture: Texture2D:
	set(value):
		mask_texture = value
		_sync_material()
## 要显示的图片；留空时绘制纯色遮罩。
@export var content_texture: Texture2D:
	set(value):
		content_texture = value
		_sync_material()
## 纯色遮罩的颜色；设置内容图片后不使用此颜色。
@export var tint: Color = Color.BLACK:
	set(value):
		tint = value
		_sync_material()
## 显示进度：0 完全隐藏，1 完全显示。
@export_range(0.0, 1.0, 0.01) var progress: float = 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		_sync_material()
## 反转遮罩灰度顺序，与播放方向相互独立。
@export var inverted: bool = false:
	set(value):
		inverted = value
		_sync_material()

## 播放目标端：完全隐藏的 0.0 或完全显示的 1.0。[method play] 从当前 [member progress]
## 到达该值；一个节点只负责一条显隐路径，双向由两个目标端不同的实例分属两个宿主表达。
@export_range(0.0, 1.0, 0.01) var target_progress: float = 1.0

@export_group("播放效果")
## 显隐动画时长（秒）；0 视为立即完成（同步发完成信号）。
@export_range(0.0, 10.0, 0.01, "or_greater", "suffix:s") var animation_duration: float = 1.0

## 动画过渡类型。
@export var animation_transition: Tween.TransitionType = Tween.TRANS_LINEAR

## 动画缓动类型。
@export var animation_ease: Tween.EaseType = Tween.EASE_IN_OUT

@export_group("动画预览")
## 仅编辑器生效的单次演出预览（快照与恢复由共享 AnimationPreview 承载）；
## 运行时调用无副作用。
@export_tool_button("播放一次", "Play") var preview_play_action: Callable = preview_play
@export_tool_button("停止并恢复", "Stop") var preview_stop_action: Callable = preview_stop

var _shader_material: ShaderMaterial
var _white_texture: GradientTexture2D
var _tween: Tween
## 宿主级整树预览会话标记（编辑器内由 QuickUiAnimHost 开关）：开启时等效本组件预览——
## 解锁编辑器空闲隔离与完成信号发射。
var _host_preview_active := false

## 创建独立材质，避免多个遮罩互相影响。
func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	_white_texture = GradientTexture2D.new()
	_white_texture.gradient = Gradient.new()
	_white_texture.gradient.colors = PackedColorArray([Color.WHITE, Color.WHITE])
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = MASK_SHADER
	_sync_material()

func _ready() -> void:
	_sync_material()
	_connect_ui_tracking()

## 节点离开场景树时清理动画、恢复预览会话并断开 ui 跟随接线。
func _exit_tree() -> void:
	preview_stop()
	_stop()
	_disconnect_ui_tracking()

## 矩形跟随的采样帧：把遮罩矩形对齐目标的当前画布矩形。
func _process(_delta: float) -> void:
	_sync_rect_from_ui()

# ---------- 播放契约 ----------

## 统一播放契约（宿主经树序时间线驱动，散装用法由调用方直调）：从当前 [member progress]
## 到达 [member target_progress]；已处目标端且动画静止时先把进度归位到另一端点再起播，
## 每轮演出都有完整行程。返回是否实际起播或正在播（false = 目标端无效，宿主据此把该步
## 视为无操作跳过）。时长不大于 0 时立即落位并在调用帧内同步发 [signal play_finished]
## （调用方须先连接完成信号再起播）。编辑器空闲态拒绝起播（编辑器预览与宿主整树预览
## 会话内放行）。
func play() -> bool:
	if not is_inside_tree():
		push_error("QuickMask.play() requires a node inside the scene tree.")
		return false
	if Engine.is_editor_hint() and not is_previewing() and not _host_preview_active:
		return false
	var at_target := not is_animating() and is_equal_approx(progress, target_progress)
	# 起播前对齐一次，使演出首帧的遮罩矩形与目标一致。
	_sync_rect_from_ui()
	_stop()
	if at_target:
		_place_initial_progress()
	if animation_duration <= 0.0:
		progress = target_progress
		_emit_finished()
		return true
	_tween = create_tween()
	_tween.set_trans(animation_transition).set_ease(animation_ease)
	_tween.tween_property(self, "progress", target_progress, animation_duration)
	_tween.finished.connect(_on_finished)
	return true

## 自身显隐动画是否进行中（供宿主步骤等待与联动方判断完成时机）。
func is_animating() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()

## 装载铺场契约（宿主装载时调用）：目标为完全显示的节点先把进度瞬时置为隐藏——
## 弥合装载帧到起播前的闪现；目标为完全隐藏的节点保持现状（其呈现由显示路径维护）。
func prepare_play() -> void:
	if Engine.is_editor_hint():
		return
	if target_progress >= 0.5:
		_place_initial_progress()

# ---------- ui 矩形跟随 ----------

## 接线目标矩形跟随（装载路径在 _ready、运行时改目标在 ui setter）：目标的 resized /
## item_rect_changed 即时对齐位移与尺寸，逐帧采样把不发信号的变换变化（目标自身缩放、
## 祖先变换）带进对齐；接线后立即对齐一次。
func _connect_ui_tracking() -> void:
	if not is_instance_valid(ui):
		set_process(false)
		return
	if not ui.resized.is_connected(_sync_rect_from_ui):
		ui.resized.connect(_sync_rect_from_ui)
	if not ui.item_rect_changed.is_connected(_sync_rect_from_ui):
		ui.item_rect_changed.connect(_sync_rect_from_ui)
	set_process(is_inside_tree())
	_sync_rect_from_ui()


## 断开目标接线并停止采样（目标为空时遮罩回到自呈现，摆位由作者负责）。
func _disconnect_ui_tracking() -> void:
	set_process(false)
	if not is_instance_valid(ui):
		return
	if ui.resized.is_connected(_sync_rect_from_ui):
		ui.resized.disconnect(_sync_rect_from_ui)
	if ui.item_rect_changed.is_connected(_sync_rect_from_ui):
		ui.item_rect_changed.disconnect(_sync_rect_from_ui)


## 把遮罩矩形对齐到目标的当前画布矩形（get_global_rect 含目标自身与祖先的缩放）；
## 矩形自此是派生态（authored 锚点 / 尺寸让位于跟随），预览恢复后重新对齐目标。
func _sync_rect_from_ui() -> void:
	if not is_instance_valid(ui) or not is_inside_tree() or not ui.is_inside_tree():
		return
	var rect := ui.get_global_rect()
	# 同值跳过：接线与采样都会执行，避免无谓的重绘通知与编辑器场景脏标记。
	if global_position != rect.position:
		global_position = rect.position
	if size != rect.size:
		size = rect.size

## 将当前属性同步到显示纹理和 shader。
func _sync_material() -> void:
	if _shader_material == null:
		return
	# 仅在资源变化时赋值，避免检查器重建打断进度滑条拖动。
	if material != _shader_material:
		material = _shader_material
	var desired_texture: Texture2D = content_texture if content_texture != null else _white_texture
	if texture != desired_texture:
		texture = desired_texture
	_shader_material.set_shader_parameter("mask_texture", mask_texture)
	_shader_material.set_shader_parameter("has_mask", mask_texture != null)
	_shader_material.set_shader_parameter("use_content", content_texture != null)
	_shader_material.set_shader_parameter("tint", tint)
	_shader_material.set_shader_parameter("progress", progress)
	_shader_material.set_shader_parameter("inverted", inverted)

## 按名称选择内置图案；名称无效时返回 false，保留原图案。
func set_pattern(pattern_name: String) -> bool:
	if not PATTERNS.has(pattern_name):
		return false
	mask_texture = PATTERNS[pattern_name]
	return true

## 归位：把进度瞬时铺到目标端的另一端点（目标为完全显示则铺隐藏，反之铺显示），使
## 本轮演出获得完整行程；起播归位、编辑器预览与装载铺场共用。
func _place_initial_progress() -> void:
	progress = 0.0 if target_progress >= 0.5 else 1.0

## 停止进行中的动画并保留当前进度，不发出完成信号；中途取消由宿主取消路径承担。
func _stop() -> void:
	if _tween != null:
		_tween.kill()
		_tween = null

## 完成信号发射口径：仅在运行时或宿主整树预览会话期间外发——编辑器空闲（含本组件
## 单次预览）静默；宿主预览的步骤等待依赖完成信号（见预览规范）。
func _emit_finished() -> void:
	if not Engine.is_editor_hint() or _host_preview_active:
		play_finished.emit()

## 动画自然结束时收尾：清空 tween 引用后按上条口径发射完成信号。
func _on_finished() -> void:
	_tween = null
	_emit_finished()

## 宿主级整树预览会话开启（QuickUiAnimHost 编辑器预览调用）：解锁编辑器隔离与完成
## 信号发射，并把进度铺到目标端的另一端点（authored 状态由宿主的 AnimationPreview
## 快照恢复）。
func _begin_host_preview_session() -> void:
	_host_preview_active = true
	_place_initial_progress()


## 宿主级整树预览会话结束：杀掉进行中的显隐动画（authored 状态由宿主快照恢复，
## 遮罩矩形随下一帧采样对齐目标）。
func _end_host_preview_session() -> void:
	_host_preview_active = false
	_stop()

#region 编辑器单次预览

var _preview := AnimationPreview.new()


## 仅在编辑器播放一趟：先把进度铺到目标端的另一端点，再播放到达目标，结束后恢复
## 编辑状态；再次点击从原编辑状态重新开始。
func preview_play() -> void:
	if not Engine.is_editor_hint():
		return
	preview_stop()
	_stop_sibling_previews()
	var properties: Array[StringName] = []
	properties.append_array(AnimationPreview.PRESENTATION_PROPERTIES)
	properties.append_array(AnimationPreview.GEOMETRY_PROPERTIES)
	if not _preview.begin(self, properties, false):
		return
	# 播放只改 progress；遮罩参数是 authored 值不在回滚范围，进度随预览回滚。
	_preview.capture(self, [&"progress"])
	_preview_run(_preview.generation)


func is_previewing() -> bool:
	return _preview.is_active()


## 保存前和退出树同步恢复；不依赖 Inspector 选择或插件生命周期。
func preview_stop() -> void:
	if not is_previewing():
		return
	_stop()
	_preview.stop()
	# ui 耦合时矩形是派生态：快照恢复 authored 几何后重新对齐目标。
	_sync_rect_from_ui()


func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		preview_stop()


## 同目标互斥：起播前停掉同级其它演出组件的预览会话——两个组件并发预览同一
## 宿主会互相踩对方的快照恢复；宿主（QuickUiAnimHost）名下时先停宿主的整树预览会话。
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
	# 等当前布局帧完成；停止或重播后旧轮不能再初始化。
	await get_tree().process_frame
	if not _preview.is_current(token) or not is_inside_tree():
		return
	_place_initial_progress()
	play()
	await _preview.wait_tween(self, _tween, token, animation_duration + 2.0)
	if _preview.is_current(token):
		preview_stop()

#endregion
