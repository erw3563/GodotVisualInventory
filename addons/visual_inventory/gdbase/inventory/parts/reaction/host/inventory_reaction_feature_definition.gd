@tool
class_name InventoryReactionFeatureDefinition
extends InventoryHostFeatureDefinition
## 物品反应功能的 Host 功能定义（非输入功能）。
##
## 生成什么：装配（create_assembly）时向场景服务层以租约取得共享的
## InventoryReactionService，交给 InventoryReactionFeatureAssembly 为宿主当前
## 背包申请连锁执行器——InventoryReactionController 节点；执行器由服务按库存
## 去重、引用计数共享，同一 InventoryData 无论多少 Host 装配本功能都只有一个
## 实例。场景服务或租约不可用时装配返回 null，连锁功能不生效。
##
## 有什么用：让宿主背包自动执行物品反应——执行器监听背包的
## item_added / item_position_changed 并响应回合系统的 trigger_turn_ended，
## 逐条执行物品 ItemReactionPart 中匹配触发类型的 ItemReactionRule；
## 同时观察成功提交后的 Counter 归零，效果与重置一起提交；失败保持零，
## 可通过 find_executor(host).retry_counter(item, counter_key) 显式重试。
## reaction_delay_seconds 控制每条规则执行前的等待秒数。
## Host 换绑或销毁时由 InventoryReactionFeatureAssembly 释放引用，计数归零即
## 销毁执行器。外部系统（如回合系统）可用 find_executor() 反查某 Host 背包的执行器。


@export_range(0.0, 10.0, 0.1) var reaction_delay_seconds := 0.0


func create_assembly(context: InventoryHostFeatureContext) -> InventoryHostFeatureAssembly:
	if context.scene_services == null:
		return null
	var lease := context.scene_services.acquire_extension_service(
		InventoryReactionService, func() -> Node:
			var service := InventoryReactionService.new()
			service.animation_resolver = ItemAnimationServiceFactory.make_resolver(context.scene_services)
			return service)
	if lease == null:
		return null
	var assembly := InventoryReactionFeatureAssembly.new()
	assembly.service = lease.get_service() as InventoryReactionService
	assembly.delay = reaction_delay_seconds
	assembly.add_service_lease(lease)
	return assembly


static func find_executor(host: InventoryHost) -> InventoryReactionController:
	var services := InventorySceneServices.find_existing(host)
	if services == null:
		return null
	var service := services.get_extension_service(InventoryReactionService) as InventoryReactionService
	return service.get_executor(host.inventory_data) if service != null else null
