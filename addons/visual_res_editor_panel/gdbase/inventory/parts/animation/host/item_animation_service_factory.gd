class_name ItemAnimationServiceFactory
extends RefCounted
## 动画 Feature 的唯一创建辅助；消费者仅使用 make_resolver。
static func acquire(services: InventorySceneServices) -> InventorySceneServiceLease:
	if not is_instance_valid(services):
		return null
	var lease := services.acquire_extension_service(ItemAnimationProcessor, func() -> Node:
		var processor := ItemAnimationProcessor.new()
		processor.view_provider = SceneInventoryItemViewProvider.new(services)
		return processor)
	if lease == null:
		return null
	var processor := lease.get_service() as ItemAnimationProcessor
	if processor == null or processor.view_provider == null:
		lease.release()
		return null
	return lease

## 消费者只读解析依赖；不缓存处理器，不增加租约。
static func make_resolver(services: InventorySceneServices) -> Callable:
	var reference: WeakRef = weakref(services) if is_instance_valid(services) else null
	return func() -> ItemAnimationProcessor:
		var current := reference.get_ref() as InventorySceneServices if reference != null else null
		if not is_instance_valid(current) or current.is_queued_for_deletion():
			return null
		var processor := current.get_extension_service(ItemAnimationProcessor) as ItemAnimationProcessor
		if not is_instance_valid(processor) or processor.is_queued_for_deletion() or processor.process_mode == Node.PROCESS_MODE_DISABLED:
			return null
		return processor

## 新服务装配后的单次同步；消费注册 Host 的公开布局刷新接缝。
static func sync_existing(services: InventorySceneServices) -> void:
	if not is_instance_valid(services) or services.is_queued_for_deletion():
		return
	var provider := SceneInventoryItemViewProvider.new(services)
	var seen := {}
	for host in services.get_registered_hosts():
		var inventory := host.get("inventory_data") as InventoryData
		if inventory == null:
			continue
		for item in inventory.get_item_instances():
			if seen.has(item):
				continue
			seen[item] = true
			for view in provider.find_item_views(item):
				provider.sync_view(item, view)
	var session := services.held_item_session
	if is_instance_valid(session):
		var held := session.get_held_item()
		if held != null and not seen.has(held):
			for view in provider.find_item_views(held):
				provider.sync_view(held, view)
