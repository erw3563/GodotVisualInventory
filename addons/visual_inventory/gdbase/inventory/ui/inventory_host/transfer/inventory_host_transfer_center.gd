@tool
class_name InventoryHostTransferCenter
extends Node
## Host 级库存转移中心：每个 Host 专属一个中心，决定该 Host 的快捷转移去向，
## 把物品从 source_host 单向转移到 target_host（仅源端发起，目标端不反向）。
##
## 归属模型：中心只注册源端——源 Host 同时最多拥有一个自己的中心（冲突拒绝）；
## 目标端仅为指向引用，不被注册、不参与冲突与生命周期管理，多个中心可指向
## 同一目标 Host。需要双向转移时，两个 Host 各配一个方向相反的中心。
##
## 生成什么：推荐在源 Host 配置 transfer_target_host，由 Host 在运行时自建并
## 拥有本中心（不写入场景存档）；也可手动添加本节点拖入两端；动态场景与功能
## 装配用 bind_hosts 显式绑定。每次动作从端点读取当前 InventoryData，不缓存
## 第二套库存事实。无界面的单件／全部转移用 InventoryTransferOperations；
## 源中心收集两端 Host 的转移贡献并统一提交。

## 成功后携带实际输出实例（部分拆出为新实例，完全合并后可归零）。
## from_screen_rect 是提交前源格屏幕矩形快照——源格视觉随提交同步销毁，
## 转移动画幽灵以此为起飞点；面板不在树或物品不可解析时为空矩形，动画静默跳过。
## 源剩余实例仍属于来源库存，不从提交后实例数量推算转移量。
signal item_transferred(
	item_instance: ItemInstanceData,
	from_inventory: InventoryData,
	to_inventory: InventoryData,
	from_screen_rect: Rect2,
	item_num: int
)

## 源端；中心专属的 Host，转移发起侧，快捷转移输入来自该 Host。
@export var source_host: InventoryHost:
	set(value):
		if source_host == value:
			return
		source_host = value
		_schedule_binding_refresh()

## 目标端；仅为指向引用，不被本中心注册或管理。
@export var target_host: InventoryHost:
	set(value):
		if target_host == value:
			return
		target_host = value
		update_configuration_warnings()

## 已完成专属注册的源端实例（区别于导出字段：清空字段后仍可按实例解除注册）。
var _registered_source: InventoryHost = null


func _ready() -> void:
	_refresh_binding()


func _exit_tree() -> void:
	_release_binding()


## 动态场景的显式绑定入口，与导出字段共用同一刷新流程；源端冲突或非法时
## 拒绝并返回 false。目标端只校验引用本身，不注册。
func bind_hosts(endpoint_source: InventoryHost, endpoint_target: InventoryHost) -> bool:
	if endpoint_source == null or endpoint_target == null or endpoint_source == endpoint_target:
		push_warning("InventoryHostTransferCenter: 端点非法（空端点或两端相同）")
		return false
	source_host = endpoint_source
	target_host = endpoint_target
	if not is_node_ready():
		return true
	_refresh_binding()
	return _registered_source == endpoint_source


## 幂等解除源端专属注册并清空目标引用；不影响其它中心（含指向同目标的中心）。
func clear_host_binding() -> void:
	source_host = null
	target_host = null
	if is_node_ready():
		_refresh_binding()


## 源端与目标端是否构成可用的单向连接（源端已注册、目标有效、库存互异且非空）。
func has_complete_binding() -> bool:
	if not is_instance_valid(_registered_source) or _registered_source != source_host:
		return false
	if !is_instance_valid(target_host):
		return false
	var source_inventory := source_host.get_inventory_data()
	var target_inventory := target_host.get_inventory_data()
	if source_inventory == null or target_inventory == null:
		return false
	return source_inventory != target_inventory


## 以调用方 Host 确定来源，把物品单向转移到目标端；仅本中心的源端可作为
## 调用方（目标端或局外 Host 一律拒绝），验证物品仍属于来源库存后经
## 公共执行器提交，成功发出一次 item_transferred（携带转移前快照）。
func try_transfer_item(from_host: InventoryHost, item_instance: ItemInstanceData, requested_quantity: int = -1) -> bool:
	if !is_instance_valid(from_host) or item_instance == null:
		return false
	if from_host != source_host or _registered_source != from_host:
		return false
	var to_host := target_host
	if !is_instance_valid(to_host):
		return false
	if !from_host.is_inside_tree() or !to_host.is_inside_tree():
		return false
	var from_inventory := from_host.get_inventory_data()
	var to_inventory := to_host.get_inventory_data()
	if from_inventory == null or to_inventory == null or from_inventory == to_inventory:
		return false
	if not from_inventory.has_item_instance(item_instance):
		return false
	var transfer_snapshot := _capture_transfer_snapshot(from_inventory, item_instance)
	var binding_check := func() -> bool:
		return is_instance_valid(from_host) and is_instance_valid(to_host) and source_host == from_host \
			and target_host == to_host and _registered_source == from_host and from_host.get_connected_transfer_center() == self
	var result := InventoryHostTransferExecutor.execute(from_host, to_host, item_instance, requested_quantity, binding_check)
	if not result.success:
		return false
	item_transferred.emit(
		result.output_item,
		from_inventory,
		to_inventory,
		transfer_snapshot.get("from_screen_rect", Rect2()),
		result.actual_quantity
	)
	return true


func _schedule_binding_refresh() -> void:
	if not is_node_ready():
		return
	_refresh_binding.call_deferred()


## 重绑统一流程：先解除自身旧注册，预检源端归属，失败保持未注册。
func _refresh_binding() -> void:
	_release_binding()
	if source_host == null or !is_instance_valid(source_host):
		return
	var existing := source_host.get_connected_transfer_center()
	if existing != null and existing != self:
		push_warning(
			"InventoryHostTransferCenter: Host %s 已拥有其它转移中心，拒绝绑定" % source_host.name
		)
		return
	if not source_host.register_transfer_connection(self):
		push_warning("InventoryHostTransferCenter: 注册源端 %s 失败，保持未注册" % source_host.name)
		return
	if not source_host.inventory_configuration_changed.is_connected(_on_source_configuration_changed):
		source_host.inventory_configuration_changed.connect(_on_source_configuration_changed)
	_registered_source = source_host
	update_configuration_warnings()


## 只解除仍属于自身的源端注册，并断开配置通知；目标端无需清理。
func _release_binding() -> void:
	if is_instance_valid(_registered_source):
		if _registered_source.inventory_configuration_changed.is_connected(_on_source_configuration_changed):
			_registered_source.inventory_configuration_changed.disconnect(_on_source_configuration_changed)
		if _registered_source.get_connected_transfer_center() == self:
			_registered_source.release_transfer_connection(self)
	_registered_source = null
	update_configuration_warnings()


func _on_source_configuration_changed() -> void:
	update_configuration_warnings()


## 转移前捕获演出快照：提交前经服务层活格查询直取源格屏幕矩形（提交后源格
## 视觉随 item_removed 同步销毁，事后无从重建；服务层或源面板不可解析时
## 保持空矩形，动画静默跳过）。
func _capture_transfer_snapshot(
	from_inventory: InventoryData, item_instance: ItemInstanceData
) -> Dictionary:
	var snapshot := {"from_screen_rect": Rect2()}
	if from_inventory == null or item_instance == null:
		return snapshot
	var services := InventorySceneServices.find_existing(self)
	if services != null:
		snapshot.from_screen_rect = services.find_item_screen_rect(from_inventory, item_instance)
	return snapshot


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if source_host == null or target_host == null:
		warnings.append("转移中心需要源端与目标端两个 Host：请拖入本 Host 的去向目标")
	if source_host != null and source_host == target_host:
		warnings.append("两端为同一 Host，无法构成转移连接")
	if !has_complete_binding():
		if is_instance_valid(source_host) and is_instance_valid(target_host):
			var same_endpoints := source_host == target_host
			if not same_endpoints:
				var source_inventory := source_host.get_inventory_data()
				var target_inventory := target_host.get_inventory_data()
				if source_inventory != null and source_inventory == target_inventory:
					warnings.append("两端库存为同一对象，无法转移")
				elif source_inventory == null or target_inventory == null:
					warnings.append("端点库存未注入：库存可在运行时动态补齐，非必须序列化")
	if is_instance_valid(source_host):
		var existing := source_host.get_connected_transfer_center()
		if existing != null and existing != self:
			warnings.append("Host %s 已拥有其它转移中心，绑定冲突" % source_host.name)
	# 源端输入发起请求，两端转移功能分别审查各自方向。
	if is_instance_valid(source_host) and not _host_has_quick_transfer_feature(source_host):
		warnings.append(
			"源端 Host %s 未启用快捷转移功能，不提供快捷转移输入" % source_host.name
		)
	return warnings


## 源端功能齐备与否以 Host 已合成的输入动作集合判断（商店等功能自带
## QUICK_TRANSFER 路由，天然覆盖），不识别具体功能类型；控制器缺失时无从
## 判断，不告警。
func _host_has_quick_transfer_feature(host: InventoryHost) -> bool:
	if host == null:
		return false
	var controller := host.get_items_input_controller()
	if controller == null:
		return true
	var action_ids := controller.get_configured_action_ids()
	return InventoryInputActionIds.QUICK_TRANSFER in action_ids \
		or InventoryInputActionIds.QUICK_TRANSFER_SINGLE in action_ids
