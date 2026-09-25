@tool
class_name LogicInventoryPanelAssemblyDefinition
extends InventoryPanelAssemblyDefinition
## 提供零尺寸的空装配，供树内业务 Host 持有功能。

func create_assembly(_context: InventoryPanelAssemblyContext) -> InventoryPanelAssembly:
	return InventoryPanelAssembly.new()

func recover_assembly(context: InventoryPanelAssemblyContext) -> InventoryPanelAssembly:
	return create_assembly(context)

func validate_assembly(assembly: InventoryPanelAssembly, _context: InventoryPanelAssemblyContext) -> bool:
	return assembly != null and assembly.get_parts().is_empty() and assembly.get_input_controller() == null and assembly.has_valid_owned_nodes()
