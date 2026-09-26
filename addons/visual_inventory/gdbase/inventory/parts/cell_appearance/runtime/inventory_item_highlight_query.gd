class_name InventoryItemHighlightQuery
extends RefCounted
## 通用层物品高亮查询：是否高亮，以及高亮集合变化。
## 非 Resource：仅运行时注入，不可在检查器 @export。

signal highlight_changed

## 判断物品是否应使用高亮配色（默认不高亮）。
func is_highlighted(_item_instance_data: ItemInstanceData) -> bool:
	return false
