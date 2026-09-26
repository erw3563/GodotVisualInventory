class_name ShopTransferSettlementParticipant
extends InventoryOperationSettlementParticipant
## 同次操作的钱包条目按贡献顺序累计，库存提交前静默结算。
var payments: Array[Dictionary] = []
var _before: Dictionary = {}
var _after: Dictionary = {}
var _blocked: Dictionary = {}
var _applied := false

func batch_key() -> StringName:
	return &"shop.wallet"

func merge_from(other: InventoryOperationSettlementParticipant) -> bool:
	if not other is ShopTransferSettlementParticipant:
		return false
	payments.append_array(other.payments)
	return true

func validate() -> StringName:
	_before.clear()
	_after.clear()
	for payment in payments:
		var wallet: WalletComponentData = payment.wallet
		if wallet == null:
			return &"shop_payment_rejected"
		if not _before.has(wallet):
			_before[wallet] = wallet.value
			_after[wallet] = wallet.value
		_after[wallet] = int(_after[wallet]) + int(payment.delta)
		if int(_after[wallet]) < 0:
			return &"shop_payment_rejected"
	return &""

func apply_silent() -> bool:
	for wallet: WalletComponentData in _before:
		if wallet.value != int(_before[wallet]):
			return false
	for wallet: WalletComponentData in _after:
		_blocked[wallet] = wallet.is_blocking_signals()
		wallet.set_block_signals(true)
		wallet.value = int(_after[wallet])
	_applied = true
	return true

func rollback() -> void:
	if not _applied:
		return
	for wallet: WalletComponentData in _before:
		wallet.set_block_signals(true)
		wallet.value += int(_before[wallet]) - int(_after[wallet])
		wallet.set_block_signals(_blocked[wallet])
	_applied = false

func notify_committed() -> void:
	for wallet: WalletComponentData in _before:
		wallet.set_block_signals(_blocked[wallet])
	for wallet: WalletComponentData in _before:
		if int(_before[wallet]) != int(_after[wallet]):
			wallet.value_changed.emit(wallet.value)
