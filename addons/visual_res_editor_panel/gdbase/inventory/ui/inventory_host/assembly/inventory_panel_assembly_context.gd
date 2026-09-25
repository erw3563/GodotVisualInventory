@tool
class_name InventoryPanelAssemblyContext
extends RefCounted
## Host 传给装配定义的一次性上下文；不序列化，也不跨 Host 共享。

var host: Control
var inventory_data: InventoryData
var cell_size: Vector2
var scene_owner: Node
var view_provider: InventoryItemViewProvider



func _init(
	host_: Control,
	inventory_data_: InventoryData,
	cell_size_: Vector2,
	scene_owner_: Node,
	scene_services: InventorySceneServices = null

) -> void:
	host = host_
	inventory_data = inventory_data_
	cell_size = cell_size_
	scene_owner = scene_owner_
	view_provider = SceneInventoryItemViewProvider.new(scene_services)



## 把节点挂到 Host，并登记为 Assembly 所有。
func mount_owned_node(assembly: InventoryPanelAssembly, node: Node) -> void:
	host.add_child(node)
	if scene_owner != null:
		node.owner = scene_owner
	else:
		node.owner = host
	assembly.add_owned_node(node)
