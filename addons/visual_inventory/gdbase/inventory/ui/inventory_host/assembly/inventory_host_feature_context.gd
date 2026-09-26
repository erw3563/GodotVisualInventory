class_name InventoryHostFeatureContext
extends RefCounted
## Host 传给扩展的一次性运行时上下文；不序列化、不跨 Host 共享。

var host: InventoryHost
var inventory_data: InventoryData
var inventory_owner: Node
var panel_assembly: InventoryPanelAssembly
var input_controller: InventoryItemsInputController
var scene_services: InventorySceneServices
var is_editor_preview: bool = false


func _init(
	host_: InventoryHost,
	inventory_data_: InventoryData,
	inventory_owner_: Node,
	panel_assembly_: InventoryPanelAssembly,
	input_controller_: InventoryItemsInputController,
	scene_services_: InventorySceneServices,
	is_editor_preview_: bool
) -> void:
	host = host_
	inventory_data = inventory_data_
	inventory_owner = inventory_owner_
	panel_assembly = panel_assembly_
	input_controller = input_controller_
	scene_services = scene_services_
	is_editor_preview = is_editor_preview_


func mount_owned_node(
	assembly: InventoryHostFeatureAssembly,
	node: Node
) -> void:
	host.add_child(node)
	if host.owner != null:
		node.owner = host.owner
	else:
		node.owner = host
	assembly.add_owned_node(node)
