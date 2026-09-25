class_name InventoryInputMapSetup
extends RefCounted
## 为本插件库存输入补齐 InputMap 动作与默认按键，并可写入 ProjectSettings。
## 已存在且已有绑定的动作保持原样，不覆盖用户自定义。

const DEFAULT_DEADZONE := 0.5


## 确保 [member InventoryInputActionIds.ALL] 中的动作已注册并带有默认绑定。
## persist_to_project 为 true 时，把新建或补绑结果写入 ProjectSettings 并保存。
## 返回键：created（新建动作）、bound（补上事件）、skipped（已有绑定而跳过）。
static func ensure_bindings(persist_to_project: bool = true) -> Dictionary:
	var created: Array[StringName] = []
	var bound: Array[StringName] = []
	var skipped: Array[StringName] = []
	var project_changed := false

	for action_id in InventoryInputActionIds.ALL:
		var setting_path := "input/" + str(action_id)
		var defaults := _default_events_for(action_id)
		var setting_events: Array = []
		var deadzone := DEFAULT_DEADZONE

		if ProjectSettings.has_setting(setting_path):
			var setting: Variant = ProjectSettings.get_setting(setting_path)
			if setting is Dictionary:
				deadzone = float(setting.get("deadzone", DEFAULT_DEADZONE))
				setting_events = setting.get("events", []) as Array
		elif persist_to_project:
			ProjectSettings.set_setting(setting_path, {
				"deadzone": DEFAULT_DEADZONE,
				"events": defaults.duplicate(),
			})
			setting_events = defaults.duplicate()
			project_changed = true

		var events_to_apply: Array = setting_events if not setting_events.is_empty() else defaults

		if not InputMap.has_action(action_id):
			InputMap.add_action(action_id, deadzone)
			for event: InputEvent in events_to_apply:
				if event != null:
					InputMap.action_add_event(action_id, event)
			created.append(action_id)
			bound.append(action_id)
			if persist_to_project:
				_write_project_setting(action_id)
				project_changed = true
			continue

		if InputMap.action_get_events(action_id).is_empty():
			for event: InputEvent in events_to_apply:
				if event != null:
					InputMap.action_add_event(action_id, event)
			bound.append(action_id)
			if persist_to_project:
				_write_project_setting(action_id)
				project_changed = true
		else:
			skipped.append(action_id)

	if persist_to_project and project_changed:
		var save_error := ProjectSettings.save()
		if save_error != OK:
			push_warning(
				"InventoryInputMapSetup：ProjectSettings.save 失败（错误码 %d），本次改动仅在内存中生效。"
				% save_error
			)

	return {
		"created": created,
		"bound": bound,
		"skipped": skipped,
	}


## 把当前 InputMap 中指定动作的死区与事件写回 ProjectSettings（不立刻 save）。
static func _write_project_setting(action_id: StringName) -> void:
	var events: Array = []
	for event in InputMap.action_get_events(action_id):
		events.append(event)
	ProjectSettings.set_setting("input/" + str(action_id), {
		"deadzone": InputMap.action_get_deadzone(action_id),
		"events": events,
	})


## 返回插件演示项目使用的默认输入事件。
static func _default_events_for(action_id: StringName) -> Array[InputEvent]:
	match action_id:
		InventoryInputActionIds.PRIMARY:
			return [_mouse_button(MOUSE_BUTTON_LEFT)]
		InventoryInputActionIds.PRIMARY_SINGLE:
			return [_mouse_button(MOUSE_BUTTON_LEFT, false, true)]
		InventoryInputActionIds.QUICK_TRANSFER:
			return [_mouse_button(MOUSE_BUTTON_LEFT, true, false)]
		InventoryInputActionIds.QUICK_TRANSFER_SINGLE:
			return [_mouse_button(MOUSE_BUTTON_LEFT, true, true)]
		InventoryInputActionIds.ROTATE:
			return [_mouse_button(MOUSE_BUTTON_RIGHT)]
		InventoryInputActionIds.OPEN:
			return [_mouse_button(MOUSE_BUTTON_MIDDLE)]
		InventoryInputActionIds.DESCRIBE:
			return [_physical_key(KEY_R)]
		_:
			return []


## 构造鼠标按键事件；shift_pressed / ctrl_pressed 对应修饰键。
static func _mouse_button(
	button_index: MouseButton,
	shift_pressed: bool = false,
	ctrl_pressed: bool = false
) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button_index
	event.shift_pressed = shift_pressed
	event.ctrl_pressed = ctrl_pressed
	match button_index:
		MOUSE_BUTTON_LEFT:
			event.button_mask = MOUSE_BUTTON_MASK_LEFT
		MOUSE_BUTTON_RIGHT:
			event.button_mask = MOUSE_BUTTON_MASK_RIGHT
		MOUSE_BUTTON_MIDDLE:
			event.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	return event


## 构造物理键码事件（与演示项目 inventory_describe 一致）。
static func _physical_key(physical_keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = physical_keycode
	return event
