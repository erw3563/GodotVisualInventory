@tool
@abstract
class_name InventoryPanelAssemblyDefinition
extends Resource
## 库存面板装配扩展协议。
## 具体 Definition 负责创建、恢复、绑定、尺寸口径与布局专属校验。
## 协议基类禁止实例化；每种库存 UI 必须由语义明确的具体子类完成装配。

## 单位格像素尺寸；Host 经装配 Context 下发到布局面板与手持视图。
@export var cell_size: Vector2 = Vector2(48, 48):
	set(value):
		var next := Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
		if cell_size == next:
			return
		cell_size = next
		emit_changed()


func create_assembly(_context: InventoryPanelAssemblyContext) -> InventoryPanelAssembly:
	push_error("%s 未实现 create_assembly" % get_class())
	return null


func recover_assembly(_context: InventoryPanelAssemblyContext) -> InventoryPanelAssembly:
	return null


func validate_assembly(
	assembly: InventoryPanelAssembly,
	_context: InventoryPanelAssemblyContext
) -> bool:
	return assembly != null and assembly.has_valid_owned_nodes()


func refresh_assembly(
	_assembly: InventoryPanelAssembly,
	_context: InventoryPanelAssemblyContext
) -> void:
	pass


func get_preferred_size(
	_assembly: InventoryPanelAssembly,
	_context: InventoryPanelAssemblyContext
) -> Vector2:
	return Vector2.ZERO


func teardown_assembly(assembly: InventoryPanelAssembly) -> void:
	if assembly != null:
		assembly.teardown()
