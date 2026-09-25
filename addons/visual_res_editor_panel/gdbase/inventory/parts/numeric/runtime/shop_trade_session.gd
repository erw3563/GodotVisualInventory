class_name ShopTradeSession
extends Node
## 本 Host 的交易策略与钱包服务，消费功能显式借用。
@export var stock_inventory: InventoryData
var active := true
var revision := 0
## 客户钱包。
@export var customer_wallet: WalletComponentData
## 交易策略；为空时使用商人货架默认策略。
@export var policy: ShopTradePolicy

## 运行时覆盖：关闭后取出不结算。
var _take_trade_override_enabled: bool = true
## 运行时覆盖：关闭后放入不结算。
var _put_trade_override_enabled: bool = true

var _cost_calculator: ShopInteractionCostCalculator = ShopInteractionCostCalculator.new()


## 绑定客户钱包（战斗开始等时机注入）。
func setup_customer(wallet: WalletComponentData) -> void:
	customer_wallet = wallet


## 临时开关取出结算（如胜利选物免费取出）。
func set_take_trade_enabled(enabled: bool) -> void:
	_take_trade_override_enabled = enabled


## 临时开关放入结算。
func set_put_trade_enabled(enabled: bool) -> void:
	_put_trade_override_enabled = enabled


## 当前是否对取出结算。
func is_take_trade_active() -> bool:
	return _take_trade_override_enabled and _get_policy().take_trade_enabled


## 当前是否对放入结算。
func is_put_trade_active() -> bool:
	return _put_trade_override_enabled and _get_policy().put_trade_enabled


## 当前是否对旋转结算。
func is_rotate_trade_active() -> bool:
	return _get_policy().rotate_trade_enabled


#region 交互 API（物品仍在货架上）
## 从货架取出整组物品并按策略结算。
func try_take_from_stock(operation_context: InventoryOperationContext, item: ItemInstanceData) -> bool:
	if stock_inventory == null or item == null:
		return false
	var request := InventoryOperationRequest.create(operation_context, InventoryOperationRequest.Type.TAKE, item)
	request.source_inventory = stock_inventory
	return ShopTradeProcessor.execute(request, self, null).success


## 从货架取出指定数量并按实际数量结算；部分拿取返回新实例。
func try_take_quantity_from_stock(operation_context: InventoryOperationContext, item: ItemInstanceData, quantity: int) -> ItemInstanceData:
	if stock_inventory == null or item == null or quantity <= 0:
		return null
	var request := InventoryOperationRequest.create(operation_context, InventoryOperationRequest.Type.TAKE, item)
	request.source_inventory = stock_inventory
	request.requested_quantity = quantity
	var result := ShopTradeProcessor.execute(request, self, null)
	return result.output_item if result.success else null


## 将物品放入货架指定格子并结算。
func try_place_into_stock(operation_context: InventoryOperationContext, item: ItemInstanceData, cell: Vector2i) -> bool:
	return try_place_quantity_into_stock(operation_context, item, cell, -1)


## 将实例中的精确数量原子放入货架指定格并按 Plan Effects 结算。
func try_place_quantity_into_stock(
	operation_context: InventoryOperationContext, item: ItemInstanceData, cell: Vector2i, quantity: int
) -> bool:
	if stock_inventory == null or item == null:
		return false
	var request := InventoryOperationRequest.create(operation_context, InventoryOperationRequest.Type.PLACE_AT, item)
	request.target_inventory = stock_inventory
	request.target_cell = cell
	request.requested_quantity = quantity
	return ShopTradeProcessor.execute(request, null, self).success


## 允许合并地放入货架并结算。
func try_add_into_stock_with_merge(operation_context: InventoryOperationContext, item: ItemInstanceData) -> bool:
	return try_add_quantity_into_stock_with_merge(operation_context, item, -1)


## 允许合并地把实例中的精确数量原子放入货架并结算。
func try_add_quantity_into_stock_with_merge(
	operation_context: InventoryOperationContext, item: ItemInstanceData, quantity: int
) -> bool:
	if stock_inventory == null or item == null:
		return false
	var request := InventoryOperationRequest.create(operation_context,
		InventoryOperationRequest.Type.ADD_WITH_MERGE, item
	)
	request.target_inventory = stock_inventory
	request.requested_quantity = quantity
	return ShopTradeProcessor.execute(request, null, self).success


## 不合并直接放入货架并结算。
func try_add_into_stock_without_merge(operation_context: InventoryOperationContext, item: ItemInstanceData) -> bool:
	if stock_inventory == null or item == null:
		return false
	var request := InventoryOperationRequest.create(operation_context,
		InventoryOperationRequest.Type.ADD_WITHOUT_MERGE, item
	)
	request.target_inventory = stock_inventory
	return ShopTradeProcessor.execute(request, null, self).success


## 将物品合并进货架指定格并按实际合并数量结算。
func try_merge_into_stock_cell(operation_context: InventoryOperationContext, item: ItemInstanceData, cell: Vector2i) -> bool:
	return try_merge_quantity_into_stock_cell(operation_context, item, cell, -1)


## 将实例中的精确数量原子并入货架指定格并按该数量结算。
func try_merge_quantity_into_stock_cell(
	operation_context: InventoryOperationContext, item: ItemInstanceData, cell: Vector2i, quantity: int
) -> bool:
	if stock_inventory == null or item == null:
		return false
	var request := InventoryOperationRequest.create(operation_context, InventoryOperationRequest.Type.MERGE_AT, item)
	request.target_inventory = stock_inventory
	request.target_cell = cell
	request.requested_quantity = quantity
	return ShopTradeProcessor.execute(request, null, self).success


## 用物品替换货架指定格内物品：放入方结算卖出，换出方结算买入。
func try_replace_in_stock_cell(operation_context: InventoryOperationContext, item: ItemInstanceData, cell: Vector2i) -> ItemInstanceData:
	if stock_inventory == null or item == null:
		return null
	var request := InventoryOperationRequest.create(operation_context, InventoryOperationRequest.Type.REPLACE_AT, item)
	request.target_inventory = stock_inventory
	request.target_cell = cell
	var result := ShopTradeProcessor.execute(request, self, self)
	return result.replaced_item if result.success else null


## 旋转货架内物品并结算（一步 90°）。
func try_rotate_in_stock(operation_context: InventoryOperationContext, item: ItemInstanceData, rotate_step: int = 1) -> bool:
	if stock_inventory == null or item == null:
		return false
	var request := InventoryOperationRequest.create(operation_context, InventoryOperationRequest.Type.ROTATE, item)
	request.source_inventory = stock_inventory
	request.target_inventory = stock_inventory
	request.rotate_step = rotate_step
	var decision := InventoryOperationPlanner.plan(request)
	if !decision.allowed:
		return false
	if !is_rotate_trade_active():
		return InventoryOperationCommitter.commit(decision.plan).success
	_sync_calculator_from_policy()
	var rotate_signed := _cost_calculator.get_rotate_transaction_signed_for_wallet(
		item.get_item_data(), rotate_step
	)
	if !_cost_calculator.can_apply_rotate_money(item, rotate_step, customer_wallet):
		return false
	if rotate_signed == 0:
		return InventoryOperationCommitter.commit(decision.plan).success
	return ShopTradeProcessor.commit_with_payments(decision.plan, [
		{"wallet": customer_wallet, "delta": rotate_signed}
	]).success


## 尽力旋转：依次尝试 1/2/3 步，成功一步即结算该步费用。
func try_rotate_in_stock_best_effort(operation_context: InventoryOperationContext, item: ItemInstanceData) -> bool:
	if stock_inventory == null or item == null:
		return false
	if !is_rotate_trade_active():
		return stock_inventory.try_rotate_item_in_inventory_best_effort(operation_context, item)
	for rotate_step in [1, 2, 3]:
		if try_rotate_in_stock(operation_context, item, rotate_step):
			return true
	return false
#endregion


#region 预览 API（只读：不改动钱包、不搬移物品，供费用预览 UI 使用）
## 预览拿取费用：与钱包对齐的带符号金额（负=玩家支出）；取出交易未启用时返回 0。
## amount <= 0 时按物品当前数量计；与 try_take_from_stock 实付同源（共用计算器与策略）。
func preview_take_cost(item: ItemInstanceData, amount: int = -1) -> int:
	if !is_instance_valid(item):
		return 0
	if !is_take_trade_active():
		return 0
	var trade_amount := amount if amount > 0 else item.get_item_num()
	_sync_calculator_from_policy()
	return _cost_calculator.get_take_transaction_signed_for_wallet(
		item.get_item_data(), trade_amount
	)


## 预览整组放入费用：与钱包对齐的带符号金额（负=玩家支出）；放入交易未启用时返回 0。
func preview_place_cost(item: ItemInstanceData) -> int:
	if !is_instance_valid(item):
		return 0
	if !is_put_trade_active():
		return 0
	_sync_calculator_from_policy()
	return _cost_calculator.get_put_transaction_signed_for_wallet(
		item.get_item_data(), item.get_item_num()
	)


## 预览合并放入费用：按可并入数量（手持量与目标堆剩余空间取小）计。
## 与 try_merge_into_stock_cell 实付同口径，支付门禁使用 Plan 实际并入数量。
func preview_merge_cost(item: ItemInstanceData, cell: Vector2i) -> int:
	if !is_instance_valid(item) or stock_inventory == null:
		return 0
	if !is_put_trade_active():
		return 0
	var occupant := stock_inventory.get_occupy_map().get_item_in_cell(cell)
	if occupant == null:
		return 0
	var merge_amount := mini(item.get_item_num(), occupant.get_remain_space_num())
	if merge_amount <= 0:
		return 0
	_sync_calculator_from_policy()
	return _cost_calculator.get_put_transaction_signed_for_wallet(
		item.get_item_data(), merge_amount
	)


## 预览替换费用：放入方支出与换出方拿取支出两笔之和（与 try_replace_in_stock_cell 双向结算同源）。
func preview_replace_cost(item: ItemInstanceData, cell: Vector2i) -> int:
	if !is_instance_valid(item) or stock_inventory == null:
		return 0
	var occupant := stock_inventory.get_occupy_map().get_item_in_cell(cell)
	if occupant == null:
		return 0
	return preview_place_cost(item) + preview_take_cost(occupant)
#endregion


#region Transfer 支付预检（支付与搬移由 Processor 提交）
## 判断取出交易金额是否可支付（trade_amount < 0 时用物品当前数量）。
func can_afford_take(item: ItemInstanceData, trade_amount: int = -1) -> bool:
	if item == null:
		return false
	if !is_take_trade_active():
		return true
	var amount := trade_amount if trade_amount > 0 else item.get_item_num()
	_sync_calculator_from_policy()
	var transaction_signed := _cost_calculator.get_take_transaction_signed_for_wallet(
		item.get_item_data(), amount
	)
	return _cost_calculator.can_apply_trade_money(item, amount, transaction_signed, customer_wallet)


## 判断放入交易金额是否可支付。
func can_afford_put(item: ItemInstanceData, trade_amount: int = -1) -> bool:
	if item == null:
		return false
	if !is_put_trade_active():
		return true
	var amount := trade_amount if trade_amount > 0 else item.get_item_num()
	_sync_calculator_from_policy()
	var transaction_signed := _cost_calculator.get_put_transaction_signed_for_wallet(
		item.get_item_data(), amount
	)
	return _cost_calculator.can_apply_trade_money(item, amount, transaction_signed, customer_wallet)


#endregion


## 取得当前策略（未配置时回落到商人货架）。
func _get_policy() -> ShopTradePolicy:
	if policy == null:
		policy = ShopTradePolicy.make_merchant_shelf()
	return policy


## 将策略倍率同步到计算器。
func _sync_calculator_from_policy() -> void:
	var active_policy := _get_policy()
	_cost_calculator.apply_from_policy(active_policy)


## 本会话的策略、绑定及覆盖开关指纹。
func configuration_fingerprint() -> int:
	return hash([revision, active, stock_inventory, customer_wallet,
		InventoryOperationFingerprint.of(policy), _take_trade_override_enabled, _put_trade_override_enabled])
