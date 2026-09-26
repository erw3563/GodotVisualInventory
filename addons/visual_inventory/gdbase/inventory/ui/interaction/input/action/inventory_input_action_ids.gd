class_name InventoryInputActionIds
extends RefCounted
## 库存输入动作的稳定 ID 词典与物理输入映射。
##
## 词典是闭集协议：StringName 同时是 project InputMap 的动作名，
## from_event 据此把物理事件翻译成动作 ID；新增动作必须扩展本类（加 const
## 并进 ALL），页面级的动作重组合走 InventoryInputConfigurationFeatureDefinition。

## 主交互：整组拿起/放下（功能装配中常与 PRIMARY_SINGLE 成对出现）。
const PRIMARY := &"inventory_primary"
## 主交互单件变体：只拿放一个。
const PRIMARY_SINGLE := &"inventory_primary_single"
## 快捷转移：不经手持，把目标物品直接转到配对的另一背包。
const QUICK_TRANSFER := &"inventory_quick_transfer"
## 单件快捷转移：不进入手持。
const QUICK_TRANSFER_SINGLE := &"inventory_quick_transfer_single"
## 旋转：旋转手持或目标物品的朝向。
const ROTATE := &"inventory_rotate"
## 打开：把背包型物品展开为嵌套子面板。
const OPEN := &"inventory_open"
## 描述：查看目标物品的说明。
const DESCRIBE := &"inventory_describe"

## 事件翻译的匹配顺序，靠前者先认领（单件变体先于整组判定）。
const ALL: Array[StringName] = [
	PRIMARY_SINGLE,
	QUICK_TRANSFER_SINGLE,
	QUICK_TRANSFER,
	PRIMARY,
	ROTATE,
	OPEN,
	DESCRIBE,
]


## 把物理输入事件翻译成动作 ID；未按下、echo 或未映射返回空 StringName。
## 精确匹配（exact_match），ALL 顺序即匹配优先级。
static func from_event(event: InputEvent) -> StringName:
	if event == null or not event.is_pressed():
		return &""
	if event is InputEventKey and (event as InputEventKey).echo:
		return &""
	for action_id in ALL:
		if event.is_action_pressed(action_id, false, true):
			return action_id
	return &""
