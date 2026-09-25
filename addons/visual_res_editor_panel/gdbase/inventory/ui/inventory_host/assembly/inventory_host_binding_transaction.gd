class_name InventoryHostBindingTransaction
extends RefCounted
## 暂存 Host 装配换绑的运行态记录，由调用方在统一发布后认领或回退。

enum State { FAILED, APPLIED, ACCEPTED, ROLLED_BACK }

var state := State.FAILED
var reason: StringName
var host_ref: WeakRef
var previous_inventory: InventoryData
var previous_dependencies: Dictionary
var previous_assembly: InventoryHostAssembly
var candidate_assembly: InventoryHostAssembly
var candidate_inventory: InventoryData
var candidate_dependencies: Dictionary
var previous_transfer_target: InventoryHost
var candidate_transfer_target: InventoryHost
var previous_inventory_owner: Node
var candidate_inventory_owner: Node
var definition: InventoryHostDefinition
var previous_definition: InventoryHostDefinition
var candidate_nodes: Array[Dictionary] = []
var preferred_size: Vector2
var _notified := false

func is_applied() -> bool:
	return state == State.APPLIED

func preflight() -> bool:
	var host := host_ref.get_ref() as InventoryHost if host_ref != null else null
	return state == State.APPLIED and is_instance_valid(host) and host.is_inside_tree() and host._owns_binding_transaction(self)

func rollback() -> bool:
	if state == State.ROLLED_BACK:
		return true
	if not preflight():
		return false
	return (host_ref.get_ref() as InventoryHost)._finish_binding_transaction(self, false)

func accept(notify := true) -> bool:
	if not preflight():
		return false
	if not (host_ref.get_ref() as InventoryHost)._finish_binding_transaction(self, true):
		return false
	if notify:
		notify_accepted()
	return true

## 整体认领后发送一次配置通知，拥有者离场后结束通知责任。
func notify_accepted() -> void:
	if state != State.ACCEPTED or _notified:
		return
	_notified = true
	var host := host_ref.get_ref() as InventoryHost if host_ref != null else null
	if is_instance_valid(host) and host.is_inside_tree() and not host.is_queued_for_deletion():
		host._emit_configuration_changed()

func _release_records() -> void:
	previous_inventory = null
	previous_dependencies = {}
	previous_assembly = null
	candidate_assembly = null
	candidate_inventory = null
	candidate_dependencies = {}
	previous_transfer_target = null
	candidate_transfer_target = null
	previous_inventory_owner = null
	candidate_inventory_owner = null
	previous_definition = null
	definition = null
	candidate_nodes.clear()
