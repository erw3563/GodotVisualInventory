@tool
class_name InventorySceneServices
extends CanvasLayer
## 背包场景级通用服务层：持有手持会话、输入路由、物品动画与宿主注册表。
## 由背包宿主进入场景树时自动创建（get_or_create），使用方零配置；
## 也可在场景中预置本节点（会自动加入 GROUP_NAME 分组）以覆盖层级等配置。

const GROUP_NAME := "InventorySceneServices"
const SERVICE_LAYER := 20

## 新的背包宿主完成注册时发出；场景组装根可据此观察动态宿主。描述面板不订阅此信号。
signal inventory_host_registered(host: Node)

## 场景级手持物品会话（本节点就绪时创建并持有）。
var held_item_session: InventoryHeldItemSession

## 场景级物品动画节点（本节点就绪时创建并持有，全部背包宿主共用同一份）。
var item_animator: InventoryItemAnimator

## 唯一活动库存控制器的键盘/手柄输入路由。
var input_action_router: InventoryInputActionRouter

## 已注册的背包宿主。
var _registered_hosts: Array[Node] = []
## 扩展服务注册表：脚本类型 -> {service: Node, lease_count: int}。
var _extension_services: Dictionary = {}


func _ready() -> void:
	add_to_group(GROUP_NAME)
	_ensure_held_item_session()
	_ensure_input_action_router()
	_ensure_item_animator()


## 待挂载的服务层实例：装配期的 ready 级联里可能有多个宿主同时请求创建，
## 而 find_existing 依赖的 group 要等节点进树才生效，用静态引用去重防止重复建层。
static var _pending_services: InventorySceneServices


## 查找场景中已有的服务层；不存在时返回 null。
static func find_existing(from_node: Node) -> InventorySceneServices:
	if !is_instance_valid(from_node) or !from_node.is_inside_tree():
		return null
	return from_node.get_tree().get_first_node_in_group(GROUP_NAME) as InventorySceneServices


## 查找或创建场景级服务层（挂场景根，跨场景持久）。
## 场景装配期（根节点自身的 ready 尚未触发）根会拒绝直接 add_child
## （引擎报 "Parent node is busy setting up children"），此时改为延迟一帧挂载；
## 注册类接口只做信号连接与登记，不依赖服务层已在树内，调用方无感。
static func get_or_create(from_node: Node) -> InventorySceneServices:
	if !is_instance_valid(from_node) or !from_node.is_inside_tree():
		return null
	var existing := find_existing(from_node)
	if is_instance_valid(existing):
		return existing
	var root := from_node.get_tree().root
	var services := _pending_services
	if !is_instance_valid(services):
		services = InventorySceneServices.new()
		services.name = "InventorySceneServices"
		services.layer = SERVICE_LAYER
	if root.is_node_ready():
		root.add_child(services)
	else:
		_pending_services = services
		_mount_pending.call_deferred(root)
	return services


## 装配窗口内排队的服务层在此补挂；可能已被后续就绪路径抢先挂好，先查父节点防重复。
static func _mount_pending(root: Node) -> void:
	var services := _pending_services
	if !is_instance_valid(services):
		return
	if services.get_parent() == null:
		root.add_child(services)


## 返回已注册背包宿主列表的副本（自动剔除已失效引用）。
func get_registered_hosts() -> Array[Node]:
	_purge_invalid_hosts()
	return _registered_hosts.duplicate()


## 注册背包宿主并广播给通用订阅者；重复注册自动忽略。
func register_inventory_host(host: Node) -> void:
	if !is_instance_valid(host):
		return
	if _registered_hosts.has(host):
		return
	_purge_invalid_hosts()
	_registered_hosts.append(host)
	inventory_host_registered.emit(host)


## 注销宿主；Host 出树时调用，避免场景服务长期持有失效引用。
func unregister_inventory_host(host: Node) -> void:
	_registered_hosts.erase(host)


## 按稳定脚本类型取得唯一扩展服务并增加租约计数。
## creator 只在首次请求时调用；通用容器不识别任何具体服务类型。
func acquire_extension_service(
	service_type: Script,
	creator: Callable
) -> InventorySceneServiceLease:
	if service_type == null or not creator.is_valid():
		push_error("InventorySceneServices.acquire_extension_service: 参数无效")
		return null
	var record: Dictionary = _extension_services.get(service_type, {})
	var service := record.get("service") as Node
	if not is_instance_valid(service):
		service = creator.call() as Node
		if service == null or not is_instance_of(service, service_type):
			push_error("扩展服务工厂返回了错误类型")
			if is_instance_valid(service):
				service.queue_free()
			return null
		service.name = service_type.get_global_name()
		add_child(service)
		record = {"service": service, "lease_count": 0}
	record["lease_count"] = int(record.get("lease_count", 0)) + 1
	_extension_services[service_type] = record
	return InventorySceneServiceLease.new(self, service_type, service)


## 只读取得已装配的扩展服务；不存在时不创建、不增加租约。
func get_extension_service(service_type: Script) -> Node:
	var record: Dictionary = _extension_services.get(service_type, {})
	var service := record.get("service") as Node
	return service if is_instance_valid(service) else null


## 释放一份扩展服务租约；最后一份释放后统一销毁服务及其运行时内容。
func release_extension_service(service_type: Script, service: Node) -> void:
	if service_type == null or not _extension_services.has(service_type):
		return
	var record: Dictionary = _extension_services[service_type]
	if record.get("service") != service:
		return
	var lease_count := maxi(int(record.get("lease_count", 0)) - 1, 0)
	if lease_count > 0:
		record["lease_count"] = lease_count
		_extension_services[service_type] = record
		return
	_extension_services.erase(service_type)
	if is_instance_valid(service):
		# CanvasLayer 子树退出时仍需有效 viewport；禁用后交给队列完整销毁。
		service.process_mode = Node.PROCESS_MODE_DISABLED
		service.queue_free()


## 获取（必要时补建）场景级手持会话。
func get_held_item_session() -> InventoryHeldItemSession:
	_ensure_held_item_session()
	return held_item_session


## 获取（必要时补建）场景级物品动画节点。
func get_item_animator() -> InventoryItemAnimator:
	_ensure_item_animator()
	return item_animator


## 获取（必要时补建）场景级库存输入路由器。
func get_input_action_router() -> InventoryInputActionRouter:
	_ensure_input_action_router()
	return input_action_router


## 确保物品动画节点存在并挂载到本服务层（镜像手持会话先例）。
func _ensure_item_animator() -> void:
	if !is_instance_valid(item_animator):
		item_animator = InventoryItemAnimator.new()
		item_animator.name = "InventoryItemAnimator"
	if item_animator.get_parent() == null:
		add_child(item_animator)


func _ensure_input_action_router() -> void:
	if !is_instance_valid(input_action_router):
		input_action_router = InventoryInputActionRouter.new()
		input_action_router.name = "InventoryInputActionRouter"
	if input_action_router.get_parent() == null:
		add_child(input_action_router)


#region 背包面板解析与坐标转换
## 返回显示指定库存的已注册宿主；有可见面板者优先，无任何匹配时返回 null。
func find_inventory_host(inventory_data_to_find: InventoryData) -> Node:
	if inventory_data_to_find == null:
		return null
	var fallback_host: Node = null
	for host in get_registered_hosts():
		if host.get("inventory_data") != inventory_data_to_find:
			continue
		if _is_host_panel_visible(host):
			return host
		if fallback_host == null:
			fallback_host = host
	return fallback_host


## 宿主任一公开装配部件可见即视为可见宿主。
func _is_host_panel_visible(host: Node) -> bool:
	if not host.has_method("get_assembly_parts"):
		return false
	for panel in host.get_assembly_parts():
		if panel is CanvasItem and panel.is_visible_in_tree():
			return true
	return false


## 在显示指定库存的宿主上找具备指定方法的物品面板（GRID/FREE 各自实现查询方法）。
func _find_items_panel_for(inventory_data_to_find: InventoryData, panel_method: String) -> Node:
	var host := find_inventory_host(inventory_data_to_find)
	if host == null or not host.has_method("find_assembly_part_with_method"):
		return null
	return host.find_assembly_part_with_method(panel_method)


## 物品实例在指定库存面板中的屏幕矩形（GRID 走实例注册表，FREE 走自由格注册表）；
## 目录面板无实例级格子，无法解析时一律返回 Rect2()。
func find_item_screen_rect(inventory_data_to_find: InventoryData, item_instance_data: ItemInstanceData) -> Rect2:
	var items_panel = _find_items_panel_for(inventory_data_to_find, "get_item_box_screen_rect")
	if items_panel != null:
		var rect: Rect2 = items_panel.get_item_box_screen_rect(item_instance_data)
		if rect != Rect2():
			return rect
	var free_panel = _find_items_panel_for(inventory_data_to_find, "get_cell_for_item")
	if free_panel != null:
		var free_cell = free_panel.get_cell_for_item(item_instance_data)
		if free_cell != null:
			return free_cell.get_global_rect()
	return Rect2()


## 背包内与物品同种数据任意一堆的屏幕矩形（转移合并被吸收时的落点回退）。
func find_same_item_screen_rect(inventory_data_to_find: InventoryData, item_instance_data: ItemInstanceData) -> Rect2:
	var items_panel = _find_items_panel_for(inventory_data_to_find, "get_same_item_box_screen_rect")
	if items_panel == null:
		return Rect2()
	return items_panel.get_same_item_box_screen_rect(item_instance_data)


## 延迟物品在其面板中的图标显示（动画演出用；仅物品自有格子生效，合并幸存堆不延迟）。
func delay_item_icon_display(inventory_data_to_find: InventoryData, item_instance_data: ItemInstanceData, duration: float) -> bool:
	var items_panel = _find_items_panel_for(inventory_data_to_find, "delay_item_icon_display")
	if items_panel == null:
		return false
	return items_panel.delay_item_icon_display(item_instance_data, duration)


## 只向支持图标隐藏的面板申请展示租约；回调绑定原格子，不会误恢复后来新建的格子。
func acquire_item_icon_display_hold(inventory_data_to_find: InventoryData, item_instance_data: ItemInstanceData) -> Callable:
	var items_panel = _find_items_panel_for(inventory_data_to_find, "acquire_item_icon_display_hold")
	if items_panel == null:
		return Callable()
	return items_panel.acquire_item_icon_display_hold(item_instance_data)


## 世界坐标（Node2D 全局，含相机滚动）→ 本服务层 canvas 坐标（Control 全局位置口径）。
## 无相机且本层 transform 为恒等时，两种坐标一致。
func world_to_canvas(world_position: Vector2) -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return world_position
	var root_canvas_position: Vector2 = viewport.get_canvas_transform() * world_position
	return transform.affine_inverse() * root_canvas_position


## 本服务层 canvas 坐标 → 世界坐标（Node2D 全局）。
func canvas_to_world(canvas_position: Vector2) -> Vector2:
	var viewport := get_viewport()
	if viewport == null:
		return canvas_position
	var root_canvas_position: Vector2 = transform * canvas_position
	return viewport.get_canvas_transform().affine_inverse() * root_canvas_position
#endregion


## 确保手持会话存在、挂载到本服务层并随层渲染。
func _ensure_held_item_session() -> void:
	if !is_instance_valid(held_item_session):
		held_item_session = InventoryHeldItemSession.new()
		held_item_session.name = "InventoryHeldItemSession"
	if held_item_session.get_parent() == null:
		add_child(held_item_session)
	held_item_session.preferred_view_parent = self
	held_item_session.view_provider = SceneInventoryItemViewProvider.new(self)


## 清理已失效的宿主注册。
func _purge_invalid_hosts() -> void:
	for host_index in range(_registered_hosts.size() - 1, -1, -1):
		if !is_instance_valid(_registered_hosts[host_index]):
			_registered_hosts.remove_at(host_index)


## 已登记且仍可用的服务副本；只读协议消费，不创建功能。
func get_extension_services() -> Array[Node]:
	var result: Array[Node] = []
	for record in _extension_services.values():
		var service := record.get("service") as Node
		if is_instance_valid(service) and not service.is_queued_for_deletion():
			result.append(service)
	return result
