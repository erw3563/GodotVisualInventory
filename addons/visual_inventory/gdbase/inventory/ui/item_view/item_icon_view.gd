@tool
class_name ItemIconView
extends Control
## 唯一纹理落笔者。布局写本节点，局部反馈只写内部偏移节点。
signal playback_invalidated
var binding_generation := 0
var sync_callback: Callable
var _item_ref: WeakRef
var _base_texture: Texture2D
var _appearance_texture: Texture2D
var _appearance_owner := 0
var _sustained_texture: Texture2D
var _sustained_owner := 0
var _frame_texture: Texture2D
var _frame_owner := 0
var _feedback_owner := 0
var _offset: Control
var _texture: TextureRect

func _enter_tree() -> void:
	sync_current.call_deferred()

func _ready() -> void:
	_ensure_nodes()
	if not resized.is_connected(_update_geometry):
		resized.connect(_update_geometry)
	if not visibility_changed.is_connected(_on_visibility_changed):
		visibility_changed.connect(_on_visibility_changed)
	_update_geometry()
	sync_current()

func _exit_tree() -> void:
	playback_invalidated.emit()

func bind_item(item: ItemInstanceData) -> void:
	_ensure_nodes()
	if get_bound_item() == item:
		return
	playback_invalidated.emit()
	binding_generation += 1
	_item_ref = weakref(item) if item != null else null
	_appearance_texture = null
	_appearance_owner = 0
	_sustained_texture = null
	_sustained_owner = 0
	_frame_texture = null
	_frame_owner = 0
	_feedback_owner = 0
	_offset.rotation = 0.0
	set_base_texture(item.get_item_icon() if item != null else null)
	sync_current()

func get_bound_item() -> ItemInstanceData:
	return _item_ref.get_ref() as ItemInstanceData if _item_ref != null else null

func set_sync_callback(callback: Callable) -> void:
	sync_callback = callback
	sync_current()

func sync_current() -> void:
	if not Engine.is_editor_hint() and sync_callback.is_valid() and get_bound_item() != null:
		sync_callback.call(get_bound_item(), self)

func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		sync_current()
	else:
		playback_invalidated.emit()

func set_base_texture(value: Texture2D) -> void:
	_base_texture = value
	_resolve_texture()

func set_appearance_texture(value: Texture2D, owner_id := 0) -> void:
	_appearance_owner = owner_id
	_appearance_texture = value
	_resolve_texture()

func clear_appearance(owner_id: int) -> void:
	if _appearance_owner == owner_id:
		set_appearance_texture(null)

func set_sustained_frame(owner_id: int, value: Texture2D) -> void:
	_sustained_owner = owner_id
	_sustained_texture = value
	_resolve_texture()

func clear_sustained_frame(owner_id: int) -> void:
	if _sustained_owner != owner_id:
		return
	_sustained_owner = 0
	_sustained_texture = null
	_resolve_texture()

func has_temporary_frame() -> bool:
	return _frame_texture != null

func get_display_texture() -> Texture2D:
	_ensure_nodes()
	return _texture.texture

func set_frame(owner_id: int, value: Texture2D) -> void:
	_frame_owner = owner_id
	_frame_texture = value
	_resolve_texture()

func clear_frame(owner_id: int) -> void:
	if _frame_owner != owner_id:
		return
	_frame_owner = 0
	_frame_texture = null
	_resolve_texture()

func set_feedback_rotation(owner_id: int, value: float) -> void:
	_ensure_nodes()
	_feedback_owner = owner_id
	_offset.rotation = value

func clear_feedback(owner_id: int) -> void:
	if _feedback_owner != owner_id:
		return
	_feedback_owner = 0
	_offset.rotation = 0.0

func get_feedback_rotation() -> float:
	_ensure_nodes()
	return _offset.rotation

func _resolve_texture() -> void:
	_ensure_nodes()
	_texture.texture = _frame_texture if _frame_texture != null else (
		_sustained_texture if _sustained_texture != null else (
		_appearance_texture if _appearance_texture != null else _base_texture))

func _update_geometry() -> void:
	if not is_instance_valid(_offset):
		return
	_offset.size = size
	_offset.pivot_offset = size * 0.5

func _ensure_nodes() -> void:
	if is_instance_valid(_texture):
		return
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_offset = Control.new()
	_offset.name = "AnimationOffset"
	_offset.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_offset)
	_texture = TextureRect.new()
	_texture.name = "Texture"
	_texture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_offset.add_child(_texture)
	_texture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_update_geometry()
