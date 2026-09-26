class_name InventorySortButton
extends Button
## InventorySortButton 负责响应点击并触发背包整理。

## 需要整理的目标 Host。
@export var inventory_host: InventoryHost

func _ready() -> void:
	# 监听按钮按下事件，触发整理逻辑。
	pressed.connect(_on_pressed)

## 按钮按下后尝试整理背包。
func _on_pressed() -> void:
	if !is_instance_valid(inventory_host) or not inventory_host.input_enabled or inventory_host.inventory_data == null:
		return
	inventory_host.inventory_data.try_sort_inventory(InventoryOperationContext.for_endpoint(inventory_host.get_operation_endpoint()))
