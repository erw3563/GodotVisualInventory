class_name InventoryHostTransferContext
extends RefCounted
## 本次转移的两端身份、计划与本端业务方向。
enum Direction { OUTGOING, INCOMING }
var source_host: InventoryHost
var target_host: InventoryHost
var operation_context: InventoryOperationContext
var plan: InventoryOperationPlan
var requested_quantity := -1
var direction: Direction
