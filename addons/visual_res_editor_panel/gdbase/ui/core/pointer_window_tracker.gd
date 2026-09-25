class_name PointerWindowTracker
extends RefCounted
## 通用 UI 共享窗口指针跟踪器：经 Window 的 mouse_entered / mouse_exited 信号维护
## 「鼠标是否仍在窗口客户区内」。系统标题栏属于非客户区——离开客户区后调用方不能
## 凭旧坐标维持悬停判定。实现自面板系三脚本（ZoomPanel / RotatePanel / SideBarPanel）
## 的同构窗口跟踪逐行移植；编辑器环境（含面板预览）不跟踪——编辑器空闲态不响应
## 窗口鼠标（见《面板编辑器预览规范》第三节）。
## 挂载方式：宿主持有 `var _tracker := PointerWindowTracker.new()`，就绪时 attach(self)、
## 退出树前 detach(self)；读 `_tracker.is_pointer_in_window` 判定。

## 鼠标是否仍在窗口客户区内；attach 时视为在场，收到 mouse_exited 后翻假。
var is_pointer_in_window: bool = true


## 连接宿主所在窗口的鼠标进出信号（幂等；编辑器环境不连接）。须在宿主入树后调用。
func attach(node: Node) -> void:
	if Engine.is_editor_hint():
		return
	if node == null or not node.is_inside_tree():
		return
	var window := node.get_window()
	if window == null:
		return
	if not window.mouse_entered.is_connected(_on_mouse_entered):
		window.mouse_entered.connect(_on_mouse_entered)
	if not window.mouse_exited.is_connected(_on_mouse_exited):
		window.mouse_exited.connect(_on_mouse_exited)
	is_pointer_in_window = true


## 断开窗口鼠标进出信号（幂等）。退出树通知期间宿主仍在树内，可正常取窗口。
func detach(node: Node) -> void:
	if node == null or not node.is_inside_tree():
		return
	var window := node.get_window()
	if window == null:
		return
	if window.mouse_entered.is_connected(_on_mouse_entered):
		window.mouse_entered.disconnect(_on_mouse_entered)
	if window.mouse_exited.is_connected(_on_mouse_exited):
		window.mouse_exited.disconnect(_on_mouse_exited)


func _on_mouse_entered() -> void:
	is_pointer_in_window = true


func _on_mouse_exited() -> void:
	is_pointer_in_window = false
