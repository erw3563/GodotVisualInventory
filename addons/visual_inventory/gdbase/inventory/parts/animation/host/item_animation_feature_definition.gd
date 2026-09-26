@tool
class_name ItemAnimationFeatureDefinition
extends InventoryHostFeatureDefinition
## 物品动画功能定义（非输入功能）。
##
## 生成什么：向场景服务以租约取得共享的被动播放器 ItemAnimationProcessor
## （携带 SceneInventoryItemViewProvider）；不贡献动作路由与观察器、不挂载
## Host 局部节点，装配成功后延迟一帧把各 Host 既有物品的视图同步一次。
## 场景服务缺失或租约失败（含编辑器预览上下文）时装配返回 null，动画不生效。
##
## 有什么用：动画处理器的唯一申请入口——只有组合了本功能的 Host 所在场景才会
## 创建 ItemAnimationProcessor；反应演出与嵌套开窗经
## ItemAnimationServiceFactory.make_resolver 只读消费现有服务，不重复申请。
## 租约随 Assembly 释放，计数归零即销毁处理器。

func create_assembly(context: InventoryHostFeatureContext) -> InventoryHostFeatureAssembly:
	if context.is_editor_preview or context.scene_services == null:
		return null
	var lease := ItemAnimationServiceFactory.acquire(context.scene_services)
	if lease == null:
		return null
	var assembly := InventoryHostFeatureAssembly.new()
	assembly.add_service_lease(lease)
	ItemAnimationServiceFactory.sync_existing.call_deferred(context.scene_services)
	return assembly
