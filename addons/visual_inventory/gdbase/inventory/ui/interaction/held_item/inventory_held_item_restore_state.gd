class_name InventoryHeldItemRestoreState
extends RefCounted
## 手持会话的运行态发布记录，持有数据、来源、视图及输入帧事实。
var item: ItemInstanceData
var source_inventory: InventoryData
var endpoint: InventoryOperationEndpoint
var controller_ref: WeakRef
var source_cell := Vector2i(-1, -1)
var view: InventoryHeldItemView
var view_visible := false
var rotate_frame := -1
var revision := 0

func same_as(other: InventoryHeldItemRestoreState) -> bool:
	return other != null and item == other.item and source_inventory == other.source_inventory and endpoint == other.endpoint and controller_ref == other.controller_ref and source_cell == other.source_cell and view == other.view and view_visible == other.view_visible and rotate_frame == other.rotate_frame and revision == other.revision

func validate_view() -> bool:
	if item == null:
		return view == null or (is_instance_valid(view) and view.held_item_instance_data == null)
	return is_instance_valid(view) and view.held_item_instance_data == item and is_instance_valid(view.held_item_box)
