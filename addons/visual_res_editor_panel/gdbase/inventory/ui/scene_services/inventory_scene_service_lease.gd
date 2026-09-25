class_name InventorySceneServiceLease
extends RefCounted
## InventorySceneServices 发放的引用计数租约；释放最后一份租约时销毁扩展服务。

var _services: InventorySceneServices
var _service_type: Script
var _service: Node
var _released := false


func _init(
	services: InventorySceneServices,
	service_type: Script,
	service: Node
) -> void:
	_services = services
	_service_type = service_type
	_service = service


func get_service() -> Node:
	return _service if not _released and is_instance_valid(_service) else null


func release() -> void:
	if _released:
		return
	_released = true
	if is_instance_valid(_services):
		_services.release_extension_service(_service_type, _service)
	_services = null
	_service_type = null
	_service = null
