@tool
class_name NestedInventoryHostFeatureDefinition
extends InventoryHostFeatureDefinition
## 嵌套库存功能定义：让背包型物品（ItemInventoryPart）能被打开成子背包窗口。
##
## 生成什么：向场景服务以租约取得共享的 NestedInventoryWindowService
## （缺 InventorySceneServices 或租约失败则装配失败返回 null）；
## 挂载 Host 局部节点 NestedInventoryPartProcessor（按本功能配置选择父级功能）；
## 并注册 OPEN 动作路由，经 NestedInventoryOpenProcessor 转发给该节点。
##
## 有什么用：对背包型物品触发打开动作时，Part Processor 解析物品的嵌套
## Part/State 并经窗口服务开出可拖动浮窗 NestedInventoryWindow（内含完整
## 子 Host）；子功能显式传播并重新校验，支持递归打开（袋中袋）。
## 空允许集合不继承任何功能；递归打开须显式允许本功能类型。


## 从父 Host 继承的具体功能类型；只选择已装配项，保留父级配置与顺序。
@export var inherited_feature_types: Array[Script] = []


func validate_configuration(_features: Array[InventoryHostFeatureDefinition]) -> StringName:
	var seen: Dictionary = {}
	for feature_type in inherited_feature_types:
		if feature_type == null:
			return &"nested_inherited_feature_type_missing"
		if seen.has(feature_type):
			return &"nested_inherited_feature_type_duplicate"
		seen[feature_type] = true
		var base: Script = feature_type
		while base != null and base != InventoryHostFeatureDefinition:
			base = base.get_base_script()
		if base == null or feature_type.is_abstract():
			return &"nested_inherited_feature_type_invalid"
	return &""


func create_assembly(
	context: InventoryHostFeatureContext
) -> InventoryHostFeatureAssembly:
	var assembly := InventoryHostFeatureAssembly.new()
	if context == null or context.input_controller == null or context.host == null or context.host.definition == null:
		return null
	if context.scene_services == null:
		push_error("NestedInventoryHostFeatureDefinition: 缺少 InventorySceneServices")
		return null
	var lease := context.scene_services.acquire_extension_service(
		NestedInventoryWindowService,
		func() -> Node:
			var service := NestedInventoryWindowService.new()
			service.animation_resolver = ItemAnimationServiceFactory.make_resolver(context.scene_services)
			return service
	)
	if lease == null:
		push_error("NestedInventoryHostFeatureDefinition: 无法取得窗口服务租约")
		return null
	assembly.add_service_lease(lease)
	var service := lease.get_service() as NestedInventoryWindowService
	if service == null:
		assembly.teardown()
		return null
	var processor := NestedInventoryPartProcessor.new()
	processor.name = "NestedInventoryPartProcessor"
	processor.window_service = service
	processor.parent_features = context.host.definition.features.duplicate()
	processor.inherited_feature_types = inherited_feature_types.duplicate()
	processor.source_host = context.host
	context.mount_owned_node(assembly, processor)
	var adapter := NestedInventoryOpenProcessor.new()
	adapter.part_processor = processor
	assembly.action_routes = [
		InventoryInputActionRoute.create(
			InventoryInputActionIds.OPEN,
			[adapter]
		)
	]
	return assembly
