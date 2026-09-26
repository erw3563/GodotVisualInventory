class_name ShopInventoryBinding
extends RefCounted
## 场景拥有的运行时事实；修改后重新 bind_feature_dependency 使其生效。
## 客户端点不在此处：配置在货架 Host 的 transfer_target_host 上。
var customer_wallet: WalletComponentData
var customer_inventory: InventoryData
var trade_policy: ShopTradePolicy
