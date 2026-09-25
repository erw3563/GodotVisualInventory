class_name InventoryReactionExecutionQueue
extends RefCounted
## 按入队顺序授予执行权，跨执行器保持批次顺序。
var _next: int = 0
var _tickets: Array[int] = []

func reserve() -> int:
	_next += 1
	_tickets.append(_next)
	return _next

func can_execute(ticket: int) -> bool:
	return not _tickets.is_empty() and _tickets[0] == ticket

func release(ticket: int) -> void:
	_tickets.erase(ticket)

func is_idle() -> bool:
	return _tickets.is_empty()
