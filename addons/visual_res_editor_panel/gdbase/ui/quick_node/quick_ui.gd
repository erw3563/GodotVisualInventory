class_name QuickUI
extends RefCounted
## 快捷系共享原语：统一「布局稳定」时序与「落笔意图」枚举。
## 位置落笔契约（原 place 静态汇入点）已并入 [class QuickUiAnimHost] 中介：
## 写位置组件（QuickDrag / QuickMousePlace）只提议，经宿主按意图分发、过
## stage 链（apply_place 契约）后唯一落笔；位置演出件（QuickPopIn / QuickPopOut /
## QuickFlyTo）自行 tween 控件布局 position，宿主在步骤完成后登记其落点。
## 详见 [class QuickUiAnimHost] 类注释。

## 落笔意图：决定提议是否经 stage 链加工，以及交互落笔是否取消进行中的树序播放。
enum PlaceIntent {
	INTERACTIVE,  ## 拖拽跟手等交互落笔：取消进行中的树序播放后经 stage 链落笔。
	PRESENTATION, ## 演出端点（QuickPopIn / QuickPopOut 的屏外端点）：直写，不经 stage 加工。
	PLACEMENT,    ## 一次性定位 / 最终位登记 / 持续回收：经 stage 链落笔。
}

## 布局 position → 全局坐标：经父节点全局变换换算（父非 CanvasItem 时恒等）。
## 位置真值统一走布局 position——Control.global_position 是含 pivot/scale 的
## 变换原点，叠加快捷系缩放（QuickZoom 写 scale/pivot）期间读写会被偏移污染。
static func layout_to_global(control: Control, local: Vector2) -> Vector2:
	var parent := control.get_parent()
	if parent is CanvasItem:
		return (parent as CanvasItem).get_global_transform() * local
	return local


## 全局坐标 → 布局 position：[method layout_to_global] 的逆换算。
static func global_to_layout(control: Control, global: Vector2) -> Vector2:
	var parent := control.get_parent()
	if parent is CanvasItem:
		return (parent as CanvasItem).get_global_transform().affine_inverse() * global
	return global


## 等两帧让容器 / 锚点布局稳定（入树后采样位置、改内容后采尺寸等场景调用）。
## 等待期间节点被移除 / 释放时安全返回（如宿主移除子节点打断仍在挂起的初始化协程；
## 静态协程不绑定实例，恢复时须自行校验，避免访问已释放节点）。
static func layout_settled(node: Node) -> void:
	if node == null or not node.is_inside_tree():
		return
	var tree := node.get_tree()
	await tree.process_frame
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	await tree.process_frame
