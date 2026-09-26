@tool
@abstract
class_name InventoryItemViewProvider
extends RefCounted
## 场景隔离的精确实例查询及只读表现同步协议。
@abstract func find_item_views(item: ItemInstanceData) -> Array[ItemIconView]

func sync_view(_item: ItemInstanceData, _view: ItemIconView) -> void:
	pass
