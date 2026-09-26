@tool
class_name SceneInventoryItemViewProvider
extends InventoryItemViewProvider
var _services_ref: WeakRef

func _init(services: InventorySceneServices) -> void:
	_services_ref = weakref(services) if services != null else null

func find_item_views(item: ItemInstanceData) -> Array[ItemIconView]:
	var result: Array[ItemIconView] = []
	var services := _get_services()
	if services == null or item == null:
		return result
	for host in services.get_registered_hosts():
		if not host.is_inside_tree() or host.is_queued_for_deletion() or not host.has_method("get_assembly_parts"):
			continue
		for part in host.get_assembly_parts():
			if not part.has_method("get_item_views"):
				continue
			_append_views(result, part.get_item_views(item), item)
	var session := services.held_item_session
	if is_instance_valid(session) and is_instance_valid(session.held_item_view):
		_append_views(result, session.held_item_view.get_item_views(item), item)
	return result

func _append_views(result: Array[ItemIconView], candidates: Array, item: ItemInstanceData) -> void:
	for candidate in candidates:
		var view := candidate as ItemIconView
		if is_instance_valid(view) and not view.is_queued_for_deletion() and view.get_bound_item() == item and view.is_inside_tree() and view.is_visible_in_tree() and not result.has(view):
			result.append(view)

func sync_view(item: ItemInstanceData, view: ItemIconView) -> void:
	if not is_instance_valid(view) or view.get_bound_item() != item:
		return
	view.set_appearance_texture(null)
	var services := _get_services()
	if services == null or Engine.is_editor_hint():
		return
	for service in services.get_extension_services():
		if service is InventoryItemPresentation:
			service.sync_view(item, view)

func _get_services() -> InventorySceneServices:
	return _services_ref.get_ref() as InventorySceneServices if _services_ref != null else null


func capture_display_texture(item: ItemInstanceData) -> Texture2D:
	var views := find_item_views(item)
	if not views.is_empty():
		return views[0].get_display_texture()
	var services := _get_services()
	if services != null:
		for service in services.get_extension_services():
			if service is InventoryItemPresentation:
				var texture: Texture2D = service.get_appearance_texture(item)
				if texture != null:
					return texture
	return item.get_item_icon() if item != null else null
