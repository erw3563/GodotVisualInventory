@tool
extends PanelContainer

## 背包数据在编辑器中被修改时发出。
signal inventory_changed
## 请求在独立弹窗中打开可视化面板。
signal popup_requested

const CELL_SIZE := Vector2(48, 48)

@onready var item_data_picker: EditorResourcePicker = $MarginContainer/VBox/Toolbar/ItemDataPicker
@onready var amount_spin: SpinBox = $MarginContainer/VBox/Toolbar/AmountSpin
@onready var add_button: Button = $MarginContainer/VBox/ViewControls/AddButton
@onready var delete_button: Button = $MarginContainer/VBox/ViewControls/DeleteButton
@onready var pop_button: Button = $MarginContainer/VBox/PopButton
@onready var inventory_host: InventoryHost = $MarginContainer/VBox/ScrollContainer/InventoryViewRoot
@onready var inventory_grid_panel := inventory_host.get_assembly_part(InventoryGridPanel) as InventoryGridPanel
@onready var inventory_items_panel := inventory_host.get_assembly_part(GridInventoryItemsPanel) as GridInventoryItemsPanel
@onready var inventory_items_input_controller := inventory_host.get_items_input_controller()

var inventory_data: InventoryData
var _input_map_registered := false

static var _input_map_users := 0
static var _owned_input_actions: Array[StringName] = []


func _enter_tree() -> void:
	# 编辑器使用自己的 InputMap；只补入库存动作，不覆盖编辑器快捷键。
	if _input_map_users == 0:
		for action_id in InventoryInputActionIds.ALL:
			if InputMap.has_action(action_id):
				continue
			var setting: Dictionary = ProjectSettings.get_setting("input/" + action_id, {})
			InputMap.add_action(action_id, float(setting.get("deadzone", 0.2)))
			for event: InputEvent in setting.get("events", []):
				InputMap.action_add_event(action_id, event)
			_owned_input_actions.append(action_id)
	_input_map_users += 1
	_input_map_registered = true


func _ready() -> void:
	add_to_group("inventory_data_editor_panel")
	_sync_inventory_panels()


func _exit_tree() -> void:
	_restore_held_item_if_from_current()
	_disconnect_inventory_mutation_signals()
	if is_instance_valid(inventory_host):
		inventory_host.remove_inventory_panel()
	if !_input_map_registered:
		return
	_input_map_registered = false
	_input_map_users -= 1
	if _input_map_users == 0:
		for action_id in _owned_input_actions:
			if not InputMap.has_action(action_id):
				continue
			# 先清按下状态；否则失焦时引擎可能访问已删除动作的事件列表。
			Input.action_release(action_id)
			InputMap.erase_action(action_id)
		_owned_input_actions.clear()


## 绑定当前正在编辑的 InventoryData 资源。
func set_inventory_data_resource(new_inventory_data_resource: InventoryData) -> void:
	if new_inventory_data_resource == inventory_data:
		return
	_restore_held_item_if_from_current()
	_disconnect_inventory_mutation_signals()
	inventory_data = new_inventory_data_resource
	_connect_inventory_mutation_signals()
	_sync_inventory_panels()


## 监听背包数据改动，确保检查器能把修改写回资源。
func _connect_inventory_mutation_signals() -> void:
	if inventory_data == null:
		return
	_set_inventory_mutation_signal(inventory_data.item_added, true)
	_set_inventory_mutation_signal(inventory_data.item_removed, true)
	_set_inventory_mutation_signal(inventory_data.item_position_changed, true)
	_set_inventory_mutation_signal(inventory_data.item_rotated, true)
	_set_inventory_mutation_signal(inventory_data.item_reshaped, true)
	_set_inventory_mutation_signal(inventory_data.item_corrected, true)
	_set_inventory_mutation_signal(inventory_data.sorted, true)
	_set_inventory_mutation_signal(inventory_data.inventory_cleared, true)
	_set_inventory_mutation_signal(inventory_data.occupy_map_changed, true)


## 切换或卸载背包时断开改动监听。
func _disconnect_inventory_mutation_signals() -> void:
	if inventory_data == null:
		return
	_set_inventory_mutation_signal(inventory_data.item_added, false)
	_set_inventory_mutation_signal(inventory_data.item_removed, false)
	_set_inventory_mutation_signal(inventory_data.item_position_changed, false)
	_set_inventory_mutation_signal(inventory_data.item_rotated, false)
	_set_inventory_mutation_signal(inventory_data.item_reshaped, false)
	_set_inventory_mutation_signal(inventory_data.item_corrected, false)
	_set_inventory_mutation_signal(inventory_data.sorted, false)
	_set_inventory_mutation_signal(inventory_data.inventory_cleared, false)
	_set_inventory_mutation_signal(inventory_data.occupy_map_changed, false)


## 按目标状态连接或断开单条背包改动信号。
func _set_inventory_mutation_signal(target_signal: Signal, is_connect: bool) -> void:
	if is_connect:
		if !target_signal.is_connected(_on_inventory_mutated):
			target_signal.connect(_on_inventory_mutated)
	else:
		if target_signal.is_connected(_on_inventory_mutated):
			target_signal.disconnect(_on_inventory_mutated)


## 背包数据被改动时通知检查器提交保存。
func _on_inventory_mutated(_arg0: Variant = null, _arg1: Variant = null) -> void:
	inventory_changed.emit()


## 通知检查器提交当前背包修改。
func _emit_inventory_changed() -> void:
	inventory_changed.emit()

## 将 InventoryData 同步到运行时背包面板组件。
func _sync_inventory_panels() -> void:
	if not is_instance_valid(inventory_host):
		return
	inventory_host.inventory_data = inventory_data
	var services := InventorySceneServices.get_or_create(self)
	inventory_host.bind_held_item_session(services.get_held_item_session())
	if inventory_grid_panel:
		inventory_grid_panel.cell_size = CELL_SIZE
		inventory_grid_panel.inventory_data = inventory_data
	if inventory_items_panel:
		inventory_items_panel.inventory_grid_panel = inventory_grid_panel
		inventory_items_panel.inventory_data = inventory_data
	if inventory_items_input_controller:
		# 独立编辑面板显式组合功能；控制器不再隐式创建默认输入。
		inventory_items_input_controller.input_processing_enabled = inventory_items_input_controller.bind_action_configuration(
			InventoryStandardFeatures.create_routes(), []
		)
		inventory_items_input_controller.held_item_view_parent = self
		inventory_items_input_controller.inventory_grid_panel = inventory_grid_panel
		inventory_items_input_controller.inventory_data = inventory_data
	if inventory_grid_panel and inventory_items_input_controller:
		inventory_grid_panel.bind_items_input_controller(inventory_items_input_controller)
		var appearance := inventory_host.get_feature_assembly(InventoryCellAppearanceFeatureDefinition) as InventoryCellAppearanceFeatureAssembly
		appearance.bind_interaction(inventory_host, inventory_items_input_controller)

## 按数量 spin 向背包添加物品；超过单堆上限时分批创建实例。
## 编辑器仅设置布局字段，避免旧 @tool 字节码仍调用非工具组件方法。
func _on_add_button_pressed() -> void:
	if inventory_data == null:
		return
	var selected_item_data := item_data_picker.get_edited_resource() as ItemData
	if selected_item_data == null:
		return
	var remaining_amount := int(amount_spin.value)
	var did_change := false
	while remaining_amount > 0:
		var new_item_instance := _create_editor_safe_item_instance(selected_item_data, remaining_amount)
		var batch_amount := new_item_instance.num
		if batch_amount <= 0:
			break
		if !inventory_data.try_add_item_with_merge(InventoryOperationContext.system(), new_item_instance):
			break
		did_change = true
		remaining_amount -= batch_amount
	# 合并到已有堆叠时不会发出 item_added，需要在此补发保存通知。
	if did_change:
		_emit_inventory_changed()

## 创建用于 VisualPanel 的物品实例；编辑器跳过组件与修饰初始化。
func _create_editor_safe_item_instance(selected_item_data: ItemData, amount: int) -> ItemInstanceData:
	var new_item_instance := ItemInstanceData.new()
	if Engine.is_editor_hint():
		new_item_instance.item_data = selected_item_data
		new_item_instance.num = amount
		return new_item_instance
	new_item_instance.init(selected_item_data, amount)
	return new_item_instance

func _on_delete_button_pressed() -> void:
	if inventory_data == null:
		return
	var services := InventorySceneServices.find_existing(self)
	var held_item_session := services.get_held_item_session() if services != null else null
	if is_instance_valid(held_item_session) and held_item_session.has_held_item():
		if held_item_session.is_holding_from(inventory_data):
			held_item_session.clear_hold()
			_emit_inventory_changed()
		return
	if inventory_grid_panel == null or !inventory_grid_panel.is_mouse_in_cells():
		return
	var mouse_cell := inventory_grid_panel.get_mouse_cell()
	if mouse_cell == Vector2i(-1, -1):
		return
	var hover_item := inventory_data.get_occupy_map().get_item_in_cell(mouse_cell) as ItemInstanceData
	if hover_item == null:
		return
	if inventory_data.try_take_item(InventoryOperationContext.system(), hover_item):
		_emit_inventory_changed()

func _on_pop_button_pressed() -> void:
	popup_requested.emit()

## 若当前手持物品来自本面板背包，则放回来源格子后再清除手持显示。
func _restore_held_item_if_from_current() -> void:
	if inventory_data == null:
		return
	var services := InventorySceneServices.find_existing(self)
	var held_item_session := services.get_held_item_session() if services != null else null
	if !is_instance_valid(held_item_session) or !held_item_session.is_holding_from(inventory_data):
		return
	held_item_session.try_restore_to_source_inventory()
