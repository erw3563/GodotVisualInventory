class_name InventoryInputActionResult
extends RefCounted
## Processor 的结构化结果。HANDLED/REJECTED 均消费输入，PASS 继续链。
##
## reason_key 为稳定失败原因（如 shop_operation_rejected）供断言与反馈，
## payload 携带附加数据；consumes_input() 是输入层的消费判定。

enum Status {
	PASS,
	HANDLED,
	REJECTED,
}

var status: Status = Status.PASS
var reason_key: StringName
var payload: Variant


static func pass_result() -> InventoryInputActionResult:
	return InventoryInputActionResult.new()


static func handled(
	reason_key_: StringName = &"",
	payload_: Variant = null
) -> InventoryInputActionResult:
	var result := InventoryInputActionResult.new()
	result.status = Status.HANDLED
	result.reason_key = reason_key_
	result.payload = payload_
	return result


static func rejected(
	reason_key_: StringName,
	payload_: Variant = null
) -> InventoryInputActionResult:
	var result := InventoryInputActionResult.new()
	result.status = Status.REJECTED
	result.reason_key = reason_key_
	result.payload = payload_
	return result


func consumes_input() -> bool:
	return status == Status.HANDLED or status == Status.REJECTED
