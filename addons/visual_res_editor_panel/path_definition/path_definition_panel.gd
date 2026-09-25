@tool
extends VBoxContainer

## PathDefinition 可视化编辑面板：曲线下拉选择当前编辑的曲线并可增删曲线，
## 下方曲线编辑视图内左键拖动点／左键点击曲线加点／右键删除点；
## 修改经 paths_changed 提交回资源属性。

signal paths_changed(new_paths: Array[Curve2D])

const VIEW_MIN_SIZE := Vector2(0.0, 220.0)
const NEW_CURVE_POINTS := [Vector2(0, 0), Vector2(100, 0)]
## 视图空白处点击新建的短曲线长度（世界坐标，向右展开）。
const SHORT_CURVE_LENGTH := 40.0

const CurveEditView := preload(
	"res://addons/visual_res_editor_panel/path_definition/path_curve_edit_view.gd"
)

var definition: PathDefinition
var active_curve_index := 0

var curve_view: Control
var _curve_option: OptionButton
var _remove_curve_button: Button
var _zoom_input: SpinBox
var _center_x: SpinBox
var _center_y: SpinBox
var _width_input: SpinBox
var _height_label: Label
var _pointer_label: Label
var _reference_toggle: CheckBox
var _reference_x: SpinBox
var _reference_y: SpinBox
var _reference_w: SpinBox
var _reference_h: SpinBox

## UI 在 _init 即构建：检查器会在属性编辑器入树前调用 setup_path_definition，
## 依赖 _ready 构建会在首次 setup 时访问空视图。
func _init() -> void:
	_build_toolbar()
	curve_view = CurveEditView.new()
	curve_view.custom_minimum_size = VIEW_MIN_SIZE
	curve_view.clip_contents = true
	curve_view.paths_edited.connect(_on_view_paths_edited)
	curve_view.create_curve_requested.connect(_on_view_create_curve_requested)
	curve_view.remove_curve_requested.connect(_on_view_remove_curve_requested)
	curve_view.select_curve_requested.connect(select_curve)
	add_child(curve_view)
	_build_view_controls()
	curve_view.view_changed.connect(_sync_view_controls)
	curve_view.pointer_changed.connect(func(point: Vector2):
		_pointer_label.text = "鼠标 X: %.2f  Y: %.2f" % [point.x, point.y])
	_sync_view_controls()

func _number(grid: GridContainer, title: String, initial: float, minimum: float, maximum: float) -> SpinBox:
	var label := Label.new()
	label.text = title
	grid.add_child(label)
	var input := SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.step = 0.01
	input.value = initial
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(input)
	return input

func _build_view_controls() -> void:
	var actions := HFlowContainer.new()
	add_child(actions)
	for entry in [["适配全部", curve_view.fit_all], ["适配当前", curve_view.fit_active], ["回到原点", curve_view.reset_origin]]:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(entry[1])
		actions.add_child(button)
	var grid := GridContainer.new()
	grid.columns = 2
	add_child(grid)
	_zoom_input = _number(grid, "缩放 %", 100, 1, 10000)
	_center_x = _number(grid, "视图中心 X", 0, -10000000, 10000000)
	_center_y = _number(grid, "视图中心 Y", 0, -10000000, 10000000)
	_width_input = _number(grid, "可见宽度", 64, 0.01, 10000000)
	_zoom_input.value_changed.connect(func(value: float): curve_view.set_view(curve_view.view_center, value / 100.0))
	_center_x.value_changed.connect(_on_center_changed)
	_center_y.value_changed.connect(_on_center_changed)
	_width_input.value_changed.connect(func(value: float): curve_view.set_visible_width(value))
	_height_label = Label.new()
	add_child(_height_label)
	_pointer_label = Label.new()
	_pointer_label.text = "鼠标 X: —  Y: —"
	add_child(_pointer_label)
	_reference_toggle = CheckBox.new()
	_reference_toggle.text = "参考画布（不裁切路径）"
	_reference_toggle.button_pressed = true
	add_child(_reference_toggle)
	var reference_grid := GridContainer.new()
	reference_grid.columns = 2
	add_child(reference_grid)
	_reference_x = _number(reference_grid, "画布左上 X", 0, -10000000, 10000000)
	_reference_y = _number(reference_grid, "画布左上 Y", 0, -10000000, 10000000)
	_reference_w = _number(reference_grid, "画布宽度", 64, 1, 10000000)
	_reference_h = _number(reference_grid, "画布高度", 64, 1, 10000000)
	for input in [_reference_x, _reference_y, _reference_w, _reference_h]:
		input.value_changed.connect(_on_reference_changed)
	_reference_toggle.toggled.connect(func(_enabled: bool): _on_reference_changed(0))
	var fit_reference := Button.new()
	fit_reference.text = "适配参考画布"
	fit_reference.pressed.connect(func(): curve_view._fit_rect(curve_view.reference_rect))
	add_child(fit_reference)
	var help := Label.new()
	help.text = "滚轮缩放 · 中键平移 · 100% = 1 坐标单位 / 视图像素"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(help)

func _on_center_changed(_value: float) -> void:
	curve_view.set_view(Vector2(_center_x.value, _center_y.value), curve_view.zoom)

func _on_reference_changed(_value: float) -> void:
	curve_view.set_reference(Rect2(_reference_x.value, _reference_y.value, _reference_w.value, _reference_h.value), _reference_toggle.button_pressed)

func _sync_view_controls() -> void:
	_zoom_input.set_value_no_signal(curve_view.zoom * 100.0)
	_center_x.set_value_no_signal(curve_view.view_center.x)
	_center_y.set_value_no_signal(curve_view.view_center.y)
	_width_input.set_value_no_signal(curve_view.size.x / curve_view.zoom)
	_height_label.text = "可见高度: %.2f（随窗口比例）" % (curve_view.size.y / curve_view.zoom)

## 绑定当前正在检查器中编辑的 PathDefinition 资源。
## 换绑资源时强制视图重适配；同一资源（含提交通路回写）保持视图稳定。
func setup_path_definition(new_definition: PathDefinition) -> void:
	var is_swap := definition != new_definition
	definition = new_definition
	active_curve_index = clampi(active_curve_index, 0, _curve_count() - 1)
	_refresh_all(is_swap)

## 切换当前编辑的曲线。
func select_curve(index: int) -> void:
	active_curve_index = clampi(index, 0, maxi(_curve_count() - 1, 0))
	_refresh_all()

## 追加一条带默认两点的曲线并选中新曲线。
## 默认空数组是导出属性的只读共享默认值，列表修改必须复制后整体赋值。
func add_curve() -> void:
	if definition == null:
		return
	var curve := Curve2D.new()
	for point in NEW_CURVE_POINTS:
		curve.add_point(point)
	var new_paths: Array[Curve2D] = definition.paths.duplicate()
	new_paths.append(curve)
	definition.paths = new_paths
	active_curve_index = definition.paths.size() - 1
	_commit()

## 删除当前选中的曲线。
func remove_curve() -> void:
	if definition == null or definition.paths.is_empty():
		return
	var new_paths: Array[Curve2D] = definition.paths.duplicate()
	new_paths.remove_at(active_curve_index)
	definition.paths = new_paths
	active_curve_index = clampi(active_curve_index, 0, maxi(definition.paths.size() - 1, 0))
	_commit()

func _curve_count() -> int:
	return 0 if definition == null else definition.paths.size()

func _build_toolbar() -> void:
	var toolbar := HBoxContainer.new()
	add_child(toolbar)

	_curve_option = OptionButton.new()
	_curve_option.item_selected.connect(select_curve)
	toolbar.add_child(_curve_option)

	var add_curve_button := Button.new()
	add_curve_button.text = "添加曲线"
	add_curve_button.pressed.connect(add_curve)
	toolbar.add_child(add_curve_button)

	_remove_curve_button = Button.new()
	_remove_curve_button.text = "删除曲线"
	_remove_curve_button.pressed.connect(remove_curve)
	toolbar.add_child(_remove_curve_button)

func _refresh_all(force_fit := false) -> void:
	_refresh_toolbar()
	if curve_view == null:
		return
	curve_view.definition = definition
	curve_view.active_curve_index = active_curve_index
	curve_view.refresh(force_fit)

func _refresh_toolbar() -> void:
	if _curve_option == null:
		return
	_curve_option.clear()
	for index in _curve_count():
		_curve_option.add_item("路径 %d" % (index + 1))
	var selectable := _curve_count() > 0
	if selectable:
		_curve_option.select(active_curve_index)
	_curve_option.disabled = not selectable
	_remove_curve_button.disabled = not selectable

func _on_view_paths_edited() -> void:
	paths_changed.emit(definition.paths.duplicate())

## 视图空白处点击：在该位置新建一条向右展开的短曲线并选中它。
func _on_view_create_curve_requested(world_position: Vector2) -> void:
	if definition == null:
		return
	var curve := Curve2D.new()
	curve.add_point(world_position)
	curve.add_point(world_position + Vector2(SHORT_CURVE_LENGTH, 0))
	var new_paths: Array[Curve2D] = definition.paths.duplicate()
	new_paths.append(curve)
	definition.paths = new_paths
	active_curve_index = definition.paths.size() - 1
	_commit()

## 视图删除最后一个点：整条曲线随之移除。
func _on_view_remove_curve_requested() -> void:
	remove_curve()

func _commit() -> void:
	_refresh_all()
	paths_changed.emit(definition.paths.duplicate())
