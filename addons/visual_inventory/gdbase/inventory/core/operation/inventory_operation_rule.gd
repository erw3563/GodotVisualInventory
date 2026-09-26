@tool
@abstract
class_name InventoryOperationRule
extends Resource
## 无状态、只读的库存操作规则。

@abstract func evaluate(context: InventoryOperationRuleContext) -> InventoryOperationDecision
