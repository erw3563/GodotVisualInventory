class_name InventoryHostFeatureAssembly
extends RefCounted
## 单个 Host 的扩展运行时结果；拥有局部节点、输入贡献与场景服务租约。

var input_priority: int = 0
var action_routes: Array[InventoryInputActionRoute] = []
var action_observers: Array[InventoryInputActionObserver] = []
var _owned_nodes: Array[Node] = []
var _service_leases: Array[InventorySceneServiceLease] = []
var _torn_down := false
var transfer_contributor: InventoryHostTransferContributor


func add_owned_node(node: Node) -> void:
	if node != null and not _owned_nodes.has(node):
		_owned_nodes.append(node)


func add_service_lease(lease: InventorySceneServiceLease) -> void:
	if lease != null and not _service_leases.has(lease):
		_service_leases.append(lease)


func refresh(_context: InventoryHostFeatureContext) -> bool:
	if transfer_contributor != null:
		transfer_contributor.bind_host(_context.host)
	return true


func teardown() -> void:
	if _torn_down:
		return
	_torn_down = true
	if transfer_contributor != null:
		transfer_contributor.invalidate()
	action_routes.clear()
	action_observers.clear()
	for node in _owned_nodes:
		if not is_instance_valid(node):
			continue
		var parent := node.get_parent()
		if parent != null:
			parent.remove_child(node)
		node.queue_free()
	_owned_nodes.clear()
	for lease in _service_leases:
		if lease != null:
			lease.release()
	_service_leases.clear()

func get_operation_policy() -> InventoryOperationPolicy:
	return null

func get_transfer_contributor() -> InventoryHostTransferContributor:
	return transfer_contributor if not _torn_down else null
