class_name InventoryReactionService
extends Node
## 具体连锁服务按库存去重，场景服务管理类型租约。
var _entries: Dictionary = {}
var animation_resolver: Callable
var _runtime_providers: Array[Callable] = []

## 按库存归属提供随机源和执行队列，创建执行器前安装依赖。
func register_runtime_provider(provider: Callable) -> void:
	if not _runtime_providers.has(provider):
		_runtime_providers.append(provider)
	refresh_runtime_sources()

func unregister_runtime_provider(provider: Callable) -> void:
	_runtime_providers.erase(provider)

func refresh_runtime_sources() -> void:
	for inventory in _entries:
		_configure_runtime(inventory, _entries[inventory].controller)

func _configure_runtime(inventory: InventoryData, controller: InventoryReactionController) -> void:
	for provider in _runtime_providers:
		if not provider.is_valid():
			continue
		var dependencies: Dictionary = provider.call(inventory)
		if dependencies.is_empty():
			continue
		if not controller.is_idle():
			assert(controller.random == dependencies.random, "执行中的随机依赖必须保持一致")
			return
		controller.random = dependencies.random
		controller.execution_queue = dependencies.queue
		return

func acquire(inventory: InventoryData, delay: float, endpoint: InventoryOperationEndpoint = null) -> InventoryReactionController:
	if inventory == null:
		return null
	if endpoint != null and endpoint.validate(inventory) != &"":
		push_error("InventoryReactionService: 后台策略端点无效或库存不匹配")
		return null
	if _entries.has(inventory):
		var entry: Dictionary = _entries[inventory]
		if not is_equal_approx(entry.delay, delay) or entry.endpoint != endpoint:
			push_error("InventoryReactionService: 同库存连锁配置冲突")
			return null
		entry.count += 1
		return entry.controller
	var controller := InventoryReactionController.new()
	_configure_runtime(inventory, controller)
	controller.operation_context = InventoryOperationContext.for_endpoint(endpoint) if endpoint != null else InventoryOperationContext.system()
	controller.reaction_delay_seconds = delay
	add_child(controller)
	controller.bind_inventory_data(inventory)
	var presenter := InventoryReactionAnimationPresenter.new()
	add_child(presenter)
	presenter.bind(controller, animation_resolver)
	_entries[inventory] = {"controller": controller, "presenter": presenter, "count": 1, "delay": delay, "endpoint": endpoint}
	return controller

func release(inventory: InventoryData) -> void:
	if not _entries.has(inventory):
		return
	var entry: Dictionary = _entries[inventory]
	entry.count -= 1
	if entry.count > 0:
		return
	_entries.erase(inventory)
	entry.presenter.unbind()
	entry.presenter.queue_free()
	entry.controller.unbind_inventory_data()
	entry.controller.queue_free()

func get_executor(inventory: InventoryData) -> InventoryReactionController:
	return _entries[inventory].controller if _entries.has(inventory) else null

func _exit_tree() -> void:
	for entry in _entries.values():
		entry.presenter.unbind()
		entry.controller.unbind_inventory_data()
	_entries.clear()
