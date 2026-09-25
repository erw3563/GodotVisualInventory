class_name NestedInventoryWindowRestore
extends RefCounted
## 窗口服务持有的可逆绑定记录，覆盖现有窗口换绑与候选窗口认领。

enum State { FAILED, APPLIED, ACCEPTED, ROLLED_BACK }

var state := State.FAILED
var reason: StringName
var service_ref: WeakRef
var window: NestedInventoryWindow
var created := false
var original_item: ItemInstanceData
var target_item: ItemInstanceData
var target_inventory: InventoryData
var target_panel: InventoryPanelAssemblyDefinition
var target_features: Array[InventoryHostFeatureDefinition] = []
var target_owner: Node
var target_source_host: InventoryHost
var host_transaction: InventoryHostBindingTransaction
var _notified := false

func is_applied() -> bool:
	return state == State.APPLIED

func preflight() -> bool:
	var service := service_ref.get_ref() as NestedInventoryWindowService if service_ref != null else null
	if state != State.APPLIED or not is_instance_valid(service) or not is_instance_valid(window) or window.is_queued_for_deletion():
		return false
	if not created and not host_transaction.preflight():
		return false
	if not created and service.get_window_for_item(original_item) != window:
		return false
	var existing := service.get_window_for_item(target_item)
	return existing == null or existing == window

func rollback() -> bool:
	if state == State.ROLLED_BACK:
		return true
	if state != State.APPLIED:
		return false
	if created:
		if is_instance_valid(window):
			window.free()
	elif not host_transaction.rollback():
		return false
	state = State.ROLLED_BACK
	return true

func accept(notify := true) -> bool:
	if not preflight():
		return false
	if not (service_ref.get_ref() as NestedInventoryWindowService).accept_restored_window(self):
		return false
	if notify:
		notify_accepted()
	return true

func notify_accepted() -> void:
	if state != State.ACCEPTED or _notified:
		return
	_notified = true
	if host_transaction != null:
		host_transaction.notify_accepted()
