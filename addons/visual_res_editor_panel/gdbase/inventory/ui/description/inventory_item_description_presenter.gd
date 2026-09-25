@abstract
class_name InventoryItemDescriptionPresenter
extends Node
## 显式绑定的描述呈现协议；不注册全局组，不查找或订阅 Host。
## 共享面板只允许当前请求所有者清理；主动查看固定，新的主动查看可替换它。
var _request_owner: WeakRef
var _request_pinned := false

func request_inventory_item(request_owner: Object, item: ItemInstanceData, pinned: bool) -> bool:
	if request_owner == null or item == null:
		return false
	if not pinned and is_request_pinned():
		return false
	if not present_inventory_item(item):
		return false
	_request_owner = weakref(request_owner)
	_request_pinned = pinned
	return true

func owns_request(request_owner: Object) -> bool:
	return _request_owner != null and _request_owner.get_ref() == request_owner

func is_request_pinned() -> bool:
	return _request_pinned and _request_owner != null and _request_owner.get_ref() != null

func release_inventory_request(request_owner: Object) -> void:
	if owns_request(request_owner):
		dismiss_inventory_item()

## 面板关闭按钮也应调用此方法，解除固定并清除展示。
func dismiss_inventory_item() -> void:
	_request_owner = null
	_request_pinned = false
	clear_inventory_item()

func is_pointer_over_panel() -> bool:
	return false

@abstract func present_inventory_item(item: ItemInstanceData) -> bool

func clear_inventory_item() -> void:
	pass

## 刷新当前内容，不改变请求归属、固定状态或显隐。
func refresh_inventory_item() -> void:
	pass
