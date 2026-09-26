@tool
class_name InventoryReactionFeatureAssembly
extends InventoryHostFeatureAssembly
## 物品反应功能的 Host 功能装配。
##
## 持有共享 InventoryReactionService 的服务租约与宿主背包引用：refresh 按当前
## 库存与端点换绑连锁执行器租约，acquire 失败只拒绝后台租约并保持装配存活，
## 不同输入策略的 Host 可继续共用库存；teardown 先释放库存引用，再由基类
## 释放节点与服务租约。service 与 delay 由 Definition 在装配时注入。


var service: InventoryReactionService
var inventory: InventoryData
var delay: float
var endpoint: InventoryOperationEndpoint


func refresh(context: InventoryHostFeatureContext) -> bool:
	var new_endpoint := context.host.get_feature_dependency(InventoryReactionFeatureDefinition) as InventoryOperationEndpoint
	if inventory == context.inventory_data and endpoint == new_endpoint:
		return true
	if inventory != null:
		service.release(inventory)
	inventory = null
	endpoint = new_endpoint
	if context.inventory_data == null:
		return true
	if service.acquire(context.inventory_data, delay, endpoint) == null:
		# 只拒绝后台租约，不阻止不同输入策略的 Host 共用库存。
		return true
	inventory = context.inventory_data
	return true


func teardown() -> void:
	if inventory != null and is_instance_valid(service):
		service.release(inventory)
	inventory = null
	super.teardown()
