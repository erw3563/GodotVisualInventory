class_name InventoryOperationContext
extends RefCounted
## 一次命令的策略来源。SYSTEM 必须由无界面调用者显式选择。
enum Origin { HOST, SYSTEM }
var origin: Origin = Origin.HOST
var source_endpoint: InventoryOperationEndpoint
var target_endpoint: InventoryOperationEndpoint

static func system() -> InventoryOperationContext:
	var context := InventoryOperationContext.new()
	context.origin = Origin.SYSTEM
	return context

static func for_endpoint(endpoint: InventoryOperationEndpoint) -> InventoryOperationContext:
	return between(endpoint, endpoint)

static func between(source: InventoryOperationEndpoint, target: InventoryOperationEndpoint) -> InventoryOperationContext:
	var context := InventoryOperationContext.new()
	context.source_endpoint = source
	context.target_endpoint = target
	return context

func validate(source: InventoryData, target: InventoryData) -> StringName:
	if source != null:
		if source_endpoint == null:
			if origin != Origin.SYSTEM:
				return &"missing_operation_endpoint"
		else:
			var reason := source_endpoint.validate(source)
			if reason != &"":
				return reason
	if target != null:
		if target_endpoint == null:
			if origin != Origin.SYSTEM:
				return &"missing_operation_endpoint"
		else:
			var reason := target_endpoint.validate(target)
			if reason != &"":
				return reason
	return &""

func fingerprint() -> int:
	return hash([get_instance_id(), origin,
		source_endpoint.fingerprint() if source_endpoint != null else 0,
		target_endpoint.fingerprint() if target_endpoint != null else 0])
