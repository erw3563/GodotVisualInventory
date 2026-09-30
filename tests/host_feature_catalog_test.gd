@tool
extends EditorPlugin
## Copied into a disposable project by test-package.ps1; never enable in user projects.
const Catalog = preload("res://addons/visual_inventory/inventory_host_definition/inventory_host_feature_catalog.gd")
const Session = preload("res://addons/visual_inventory/inventory_host_definition/inventory_host_definition_editor_session.gd")
const HostPanel = preload("res://addons/visual_inventory/inventory_host_definition/inventory_host_definition_editor_panel.gd")
const OPTIONAL := "res://addons/visual_inventory/gdbase/integration/component_inventory"
var failures: Array[String] = []

func _enter_tree() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> bool:
	if not condition:
		failures.append(message)
		push_error("FAIL: " + message)
	return condition

func _run() -> void:
	if not ProjectSettings.get_setting("visual_inventory/package_test", false):
		push_error("Package tests require a disposable test project.")
		return
	for frame in 10:
		await get_tree().process_frame
	check(EditorInterface.is_plugin_enabled("visual_inventory"), "packaged plugin enabled")
	check(InputMap.has_action("inventory_primary"), "plugin registered input bindings")
	check(not DirAccess.dir_exists_absolute(OPTIONAL), "ZIP has no optional integration directory")
	var catalog := Catalog.new()
	catalog.refresh()
	check(catalog.errors.is_empty(), "absent optional root: " + str(catalog.errors))
	var normal_paths: Array = catalog.entries.map(func(entry: Dictionary): return entry.path)
	check(not catalog.find(InventoryReactionFeatureDefinition).is_empty(), "reaction discovered")
	var required_roots := Catalog.ROOTS.duplicate()
	required_roots.erase(OPTIONAL)
	catalog.refresh(required_roots)
	check(normal_paths == catalog.entries.map(func(entry: Dictionary): return entry.path), "all built-in adapters preserved")
	print("Built-in feature adapters: ", normal_paths.size())
	await _test_editor()

	check(DirAccess.make_dir_recursive_absolute(OPTIONAL) == OK, "create empty optional root")
	catalog.refresh()
	check(catalog.errors.is_empty(), "empty optional root accepted")
	check(normal_paths == catalog.entries.map(func(entry: Dictionary): return entry.path), "empty root preserves catalog")
	check(DirAccess.make_dir_recursive_absolute(OPTIONAL + "/editor") == OK, "create extension fixture")
	_write(OPTIONAL + "/fixture.gd", "@tool\nextends InventoryReactionFeatureDefinition\n")
	_write(OPTIONAL + "/editor/fixture_host_feature_editor.gd", "@tool\nextends RefCounted\nfunc describe() -> Dictionary:\n\treturn {\"type\": load(\"" + OPTIONAL + "/fixture.gd\"), \"title\": \"Fixture integration\"}\nfunc build(_form: Control) -> void:\n\tpass\nfunc diagnose(_feature: Resource, _layout: Resource, _features: Array) -> Array[Dictionary]:\n\treturn []\n")
	catalog.refresh()
	check(catalog.errors.is_empty(), "installed optional adapter accepted: " + str(catalog.errors))
	check(catalog.entries.size() == normal_paths.size() + 1, "installed optional adapter discovered recursively")
	_write(OPTIONAL + "/editor/invalid_host_feature_editor.gd", "@tool\nextends RefCounted\n")
	catalog.refresh()
	check(catalog.errors.size() == 1 and "协议不完整" in catalog.errors[0], "invalid optional adapter remains an error")
	for file in ["editor/invalid_host_feature_editor.gd", "editor/fixture_host_feature_editor.gd", "fixture.gd"]:
		DirAccess.remove_absolute(OPTIONAL + "/" + file)
	DirAccess.remove_absolute(OPTIONAL + "/editor")
	DirAccess.remove_absolute(OPTIONAL)
	_write(OPTIONAL, "A file is not an optional directory.")
	catalog.refresh()
	check(catalog.errors.size() == 1 and OPTIONAL in catalog.errors[0], "file at optional root remains an error")
	DirAccess.remove_absolute(OPTIONAL)
	var missing := "res://missing_required_features"
	catalog.refresh([missing])
	check(catalog.errors.size() == 1 and missing in catalog.errors[0], "missing required root remains an error")
	var session := Session.new()
	var target := InventoryHostDefinition.new()
	target.layout = GridInventoryPanelAssemblyDefinition.new()
	session.setup(target, get_undo_redo())
	session.feature_catalog.refresh([missing])
	check(not session.preview_feature_addition(InventoryReactionFeatureDefinition).ok, "required-root error blocks addition")
	catalog.refresh()
	check(catalog.errors.is_empty(), "refresh clears old errors")
	print("HOST_FEATURE_TESTS: ", "PASS" if failures.is_empty() else "FAIL", " (", failures.size(), " failures)")
	get_tree().quit(0 if failures.is_empty() else 1)

func _test_editor() -> void:
	var target := InventoryHostDefinition.new()
	target.layout = GridInventoryPanelAssemblyDefinition.new()
	var session := Session.new()
	session.setup(target, get_undo_redo())
	var panel := HostPanel.new()
	panel.setup(session)
	EditorInterface.get_base_control().add_child(panel)
	panel.tabs.current_tab = 1
	panel.feature_panel.open_add()
	var button: Button = panel.feature_panel._add_buttons.get(InventoryReactionFeatureDefinition)
	if check(button != null and not button.disabled, "reaction add button enabled without optional directory"):
		button.pressed.emit()
		for frame in 5:
			await get_tree().process_frame
		if check(session.entries.size() == 1, "add button created reaction draft"):
			var field: SpinBox = panel.feature_panel.form.controls.get("reaction_delay_seconds")
			if check(field != null and field.editable, "reaction parameter editable"):
				field.value = 0.7
				check(target.features.is_empty(), "editing keeps target unchanged before apply")
				check(not panel.apply_button.disabled, "apply button enabled")
				panel.apply_button.pressed.emit()
				if check(target.features.size() == 1, "apply button committed feature"):
					check(is_equal_approx(target.features[0].reaction_delay_seconds, 0.7), "apply retained parameter")
					check(ResourceSaver.save(target, "res://applied_host.tres") == OK, "save applied resource")
					var saved := ResourceLoader.load("res://applied_host.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as InventoryHostDefinition
					check(saved != null and saved.features.size() == 1 and is_equal_approx(saved.features[0].reaction_delay_seconds, 0.7), "reload retained feature and parameter")
					var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(target))
					history.undo()
					check(target.features.is_empty(), "undo applied addition")
					history.redo()
					check(target.features.size() == 1, "redo applied addition")
	panel.queue_free()
	for frame in 5:
		await get_tree().process_frame

func _write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if check(file != null, "write fixture " + path):
		file.store_string(content)
