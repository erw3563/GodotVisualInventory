@tool
class_name InventoryTargetItemDataFilter
extends InventoryTargetFilter
## 按模板引用或明确配置的资源路径匹配候选物品。

enum MatchMode { REFERENCE, REFERENCE_OR_PATH }

@export var item_data: ItemData
@export var match_mode: MatchMode = MatchMode.REFERENCE

func validate_configuration() -> StringName:
	if item_data == null or match_mode not in [MatchMode.REFERENCE, MatchMode.REFERENCE_OR_PATH]:
		return &"invalid_rule_configuration"
	return &""

func matches(item: ItemInstanceData, context: InventoryTargetQueryContext) -> bool:
	var fact := context.get_item(item)
	if fact == null or item_data == null:
		return false
	var data := fact.get_item_data()
	if data == item_data:
		return true
	return match_mode == MatchMode.REFERENCE_OR_PATH and data != null and not data.resource_path.is_empty() and data.resource_path == item_data.resource_path
