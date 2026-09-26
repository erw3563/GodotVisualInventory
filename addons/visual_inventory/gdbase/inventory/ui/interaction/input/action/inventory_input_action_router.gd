class_name InventoryInputActionRouter
extends Node
## 场景级唯一键盘/手柄路由；指针事件仍由实际 GUI 面板转发。
##
## 只持有最后激活的一个控制器：非鼠标事件交给其 handle_routed_input
## 按动作词典翻译分发，结果消费输入时标记 viewport 已处理；
## 控制器失效或输入禁用时自动清空。

var _active_controller: InventoryItemsInputController


func _ready() -> void:
	set_process_unhandled_input(true)


func set_active_controller(controller: InventoryItemsInputController) -> void:
	if !is_instance_valid(controller) or !controller.input_processing_enabled:
		return
	_active_controller = controller


func clear_active_controller(controller: InventoryItemsInputController = null) -> void:
	if controller != null and _active_controller != controller:
		return
	_active_controller = null


func get_active_controller() -> InventoryItemsInputController:
	_purge_invalid_controller()
	return _active_controller


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		return
	_purge_invalid_controller()
	if _active_controller == null:
		return
	var result: InventoryInputActionResult = _active_controller.handle_routed_input(event)
	if result != null and result.consumes_input():
		get_viewport().set_input_as_handled()


func _purge_invalid_controller() -> void:
	if !is_instance_valid(_active_controller):
		_active_controller = null
		return
	if !_active_controller.is_inside_tree() or !_active_controller.input_processing_enabled:
		_active_controller = null
