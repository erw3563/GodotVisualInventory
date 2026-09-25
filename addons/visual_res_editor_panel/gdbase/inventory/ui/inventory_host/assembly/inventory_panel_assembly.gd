@tool
class_name InventoryPanelAssembly
extends RefCounted
## 单个 InventoryHost 的运行时面板装配结果。
## Definition Resource 必须保持无状态；所有节点引用只保存在这里。

signal size_invalidated

var _parts: Dictionary = {}
var _owned_nodes: Array[Node] = []
var _input_controller: InventoryItemsInputController


## 以脚本类型注册一个公开装配部件。
func register_part(type: Script, node: Node) -> bool:
	if type == null or node == null:
		push_error("InventoryPanelAssembly.register_part: type 与 node 均不能为空")
		return false
	if not is_instance_of(node, type):
		push_error(
			"InventoryPanelAssembly.register_part: 节点 %s 不属于类型 %s"
			% [node.name, type.resource_path]
		)
		return false
	if _parts.has(type):
		push_error(
			"InventoryPanelAssembly.register_part: 类型 %s 重复注册"
			% type.resource_path
		)
		return false
	_parts[type] = node
	return true


## 查询策略公开的具体部件；Host 不需要认识该具体类型。
## 部件可能已被外部释放（teardown 幂等语义），此时返回 null 而不是触碰悬挂实例。
func get_part(type: Script) -> Node:
	if type == null or not _parts.has(type):
		return null
	var node = _parts.get(type)
	if not is_instance_valid(node):
		return null
	return node


func get_parts() -> Array[Node]:
	var result: Array[Node] = []
	for node in _parts.values():
		if is_instance_valid(node) and not result.has(node):
			result.append(node)
	return result


func find_part_with_method(method: StringName) -> Node:
	for node in get_parts():
		if node.has_method(method):
			return node
	return null


## 将节点登记为本装配拥有；teardown 只清理这些节点。
func add_owned_node(node: Node) -> void:
	if node != null and not _owned_nodes.has(node):
		_owned_nodes.append(node)


func set_input_controller(controller: InventoryItemsInputController) -> void:
	_input_controller = controller


func get_input_controller() -> InventoryItemsInputController:
	return _input_controller if is_instance_valid(_input_controller) else null


func has_valid_owned_nodes() -> bool:
	for node in _owned_nodes:
		if not is_instance_valid(node):
			return false
	return true


func notify_size_invalidated() -> void:
	size_invalidated.emit()


## 断开 Assembly 自身信号，并只销毁策略登记的节点。
func teardown() -> void:
	for connection in size_invalidated.get_connections():
		size_invalidated.disconnect(connection.callable)
	for node in _owned_nodes:
		if not is_instance_valid(node):
			continue
		var parent := node.get_parent()
		if parent != null:
			parent.remove_child(node)
		node.queue_free()
	_owned_nodes.clear()
	_parts.clear()
	_input_controller = null
