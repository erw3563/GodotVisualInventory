class_name InventoryHostTransferContributor
extends RefCounted
## 本 Host 的普通转移贡献；具体扩展覆写 prepare 提供业务结算。
var _host: WeakRef
var _revision := 0
var _active := false

func bind_host(host: InventoryHost) -> void:
	_host = weakref(host)
	_revision += 1
	_active = true

func invalidate() -> void:
	_revision += 1
	_active = false
	_host = null

func get_host() -> InventoryHost:
	return _host.get_ref() as InventoryHost if _host != null else null

func prepare(context: InventoryHostTransferContext) -> InventoryHostTransferContribution:
	var host := get_host()
	var expected := context.source_host if context.direction == InventoryHostTransferContext.Direction.OUTGOING else context.target_host
	if not _active or not is_instance_valid(host) or host != expected:
		return InventoryHostTransferContribution.rejected(&"inventory_transfer_contributor_stale")
	var revision := _revision
	var result := InventoryHostTransferContribution.new()
	result.validity_check = func() -> StringName:
		return &"" if _active and _revision == revision and is_instance_valid(host) and host.get_transfer_contributor() == self else &"inventory_transfer_contributor_stale"
	return result
