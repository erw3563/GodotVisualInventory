class_name InventoryTargetQueryResult
extends RefCounted
## 保存一次查询选中的原实例引用、几何区域与错误码。

var items: Array[ItemInstanceData] = []
var zone_cells: Array[Vector2i] = []
var has_zone := false
var error_code: StringName = &""

static func failure(code: StringName) -> InventoryTargetQueryResult:
	var result := InventoryTargetQueryResult.new()
	result.error_code = code
	return result
