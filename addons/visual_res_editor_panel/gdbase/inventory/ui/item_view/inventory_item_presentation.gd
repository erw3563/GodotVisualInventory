@abstract
class_name InventoryItemPresentation
extends Node
## UI 只认识表现同步协议，不解释具体 Part 或业务状态。
@abstract func sync_view(item: ItemInstanceData, view: ItemIconView) -> void

func get_appearance_texture(_item: ItemInstanceData) -> Texture2D:
	return null
