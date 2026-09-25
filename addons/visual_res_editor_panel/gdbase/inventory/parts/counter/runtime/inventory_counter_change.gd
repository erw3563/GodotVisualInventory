class_name InventoryCounterChange
extends RefCounted
## 一次纯计数规划结果，state 为空且无原因表示没有变化。
var reason_key: StringName
var state: ItemCounterState
var states: Array[ItemInstanceState] = []
