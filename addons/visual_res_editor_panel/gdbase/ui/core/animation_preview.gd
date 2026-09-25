class_name AnimationPreview
extends RefCounted
## 通用 UI 共享编辑器单次动画预览机制：属性快照、播放代次、有界等待与两阶段恢复。
## 实现自面板系四脚本（ZoomPanel / RotatePanel / SideBarPanel / PocketDrawerPanel）
## 逐行相同的预览家族整块抽取；各面板与快捷系演出组件（QuickZoom / QuickWobble /
## QuickPopIn / QuickPopOut / QuickMask / QuickShow）独占一个实例，仅保留触发
## （preview_play）与编排（_preview_run 引导段）。
## 硬性约束沿袭《UI编辑器动画预览规范》：仅编辑器内生效（begin 在运行时直接拒绝）；
## 等待 Tween 不能只 await finished（kill 不保证发完成信号），须逐帧查代次并有超时；
## 恢复先非几何属性再 update_minimum_size 最后几何属性；新状态不得导出或写入场景。

## 布局几何属性：恢复顺序殿后，避免容器在恢复中途重排其它属性。
const GEOMETRY_PROPERTIES: Array[StringName] = [
	&"layout_mode", &"grow_horizontal", &"grow_vertical",
	&"anchor_left", &"anchor_top", &"anchor_right", &"anchor_bottom",
	&"offset_left", &"offset_top", &"offset_right", &"offset_bottom",
]

## 表现属性：连同布局几何属性一起被子控件快照采集。
const PRESENTATION_PROPERTIES: Array[StringName] = [
	&"custom_minimum_size", &"size_flags_horizontal", &"size_flags_vertical",
	&"clip_contents", &"mouse_filter", &"visible", &"modulate",
	&"pivot_offset", &"scale", &"rotation",
]

## 当前是否有预览轮次在进行。
var _active: bool = false
## 播放代次：每轮 begin / stop 自增，旧轮协程据 token 失效。
var _generation: int = 0
var _snapshots: Array[Dictionary] = []


## 最近一次 begin / stop 产生的代次；调用方以返回值启动编排协程并作 token 校验。
var generation: int:
	get:
		return _generation


## 当前是否有预览轮次在进行。
func is_active() -> bool:
	return _active


## token 是否仍是当前轮次（活动且代次一致）。
func is_current(token: int) -> bool:
	return _active and token == _generation


## 开始一轮预览：编辑器守卫、父控件可见与有效尺寸校验通过后自增代次、
## 采集目标快照（可选连同全部后代 Control）。返回是否成功开始。
## extra_properties 为目标自身的内部状态属性表（列在几何前，先于几何恢复）。
func begin(
		target: Control,
		extra_properties: Array[StringName],
		capture_children: bool = false) -> bool:
	if not Engine.is_editor_hint() or not target.is_inside_tree():
		return false
	var parent := target.get_parent_control()
	if parent != null and not parent.is_visible_in_tree():
		push_warning("动画预览：请先显示目标控件的父控件。")
		return false
	if target.size.x <= 0.0 or target.size.y <= 0.0:
		push_warning("动画预览：目标控件尚无有效尺寸。")
		return false
	_generation += 1
	_snapshots.clear()
	capture(target, extra_properties)
	if capture_children:
		capture_children_tree(target)
	_active = true
	return true


## 采集节点指定属性的当前值（Array / Dictionary 深拷贝防快照被后续修改污染）。
func capture(node: Object, properties: Array[StringName]) -> void:
	var values: Dictionary = {}
	for property in properties:
		var value: Variant = node.get(property)
		values[property] = value.duplicate() if value is Array or value is Dictionary else value
	_snapshots.append({"node": weakref(node), "values": values})


## 递归采集全部后代 Control 的表现与布局几何属性。
func capture_children_tree(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			capture(child, PRESENTATION_PROPERTIES + GEOMETRY_PROPERTIES)
		capture_children_tree(child)


## 停止并恢复：使本轮失效（活动置假、代次自增），再按两阶段顺序恢复——
## 先非几何属性并 update_minimum_size，最后几何属性；调用方在调用前自行
## kill 自己的动画 Tween。对空快照无副作用。
func stop() -> void:
	_active = false
	_generation += 1
	var snapshots := _snapshots
	_snapshots = []
	# 内部状态由调用方列在几何前；子控件先恢复可见性/最小尺寸，再恢复矩形。
	for snapshot in snapshots:
		var node: Object = snapshot.node.get_ref()
		if not is_instance_valid(node):
			continue
		for property in snapshot.values:
			if property not in GEOMETRY_PROPERTIES:
				node.set(property, snapshot.values[property])
		if node is Control:
			node.update_minimum_size()
	for snapshot in snapshots:
		var node: Object = snapshot.node.get_ref()
		if not is_instance_valid(node):
			continue
		for property in GEOMETRY_PROPERTIES:
			if snapshot.values.has(property):
				node.set(property, snapshot.values[property])


## 有界等待 Tween 结束：Tween 被 kill 不发 finished，逐帧检查代次避免悬挂协程；
## token 失效返回 false，超时同样返回 false 由调用方恢复。runner 为发起预览的
## 宿主节点（提供 process_frame 与存活校验）。
func wait_tween(runner: Node, tween: Tween, token: int, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(maxf(timeout, 0.1) * 1000.0)
	while is_current(token) and is_instance_valid(runner) and runner.is_inside_tree():
		if tween == null or not tween.is_valid() or not tween.is_running():
			return true
		if Time.get_ticks_msec() >= deadline:
			push_warning("动画预览等待超时，已停止并恢复。")
			return false
		await runner.get_tree().process_frame
	return false


## 有界等待固定秒数：同样逐帧检查代次，token 失效返回 false。
func wait_seconds(runner: Node, seconds: float, token: int) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while is_current(token) and is_instance_valid(runner) and runner.is_inside_tree():
		if Time.get_ticks_msec() >= deadline:
			return true
		await runner.get_tree().process_frame
	return false
