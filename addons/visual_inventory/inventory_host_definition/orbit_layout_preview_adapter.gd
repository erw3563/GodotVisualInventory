@tool
extends Node
## 只驱动弹窗内轨道的公开 rotation/relayout_slots，不解除运行时节点的编辑器守卫。
var track: OrbitTrack
var playing := true
var dragging := false
var rest_rotation := 0.0
var pointer_angle := 0.0
var snap_tween: Tween

func attach(value: OrbitTrack) -> void:
	stop()
	track = value
	playing = true

func _process(delta: float) -> void:
	if not is_instance_valid(track):
		return
	if playing and track.auto_spin and not dragging and snap_tween == null:
		track.rotation += track.rotation_speed * delta
		track.relayout_slots()

func _input(event: InputEvent) -> void:
	if handle_pointer(event):
		get_viewport().set_input_as_handled()

func handle_pointer(event: InputEvent) -> bool:
	if not is_instance_valid(track) or not playing:
		return false
	if event is InputEventMouseButton and event.button_index == track.rotary_mouse_button:
		if not event.pressed and dragging:
			dragging = false
			begin_return()
			return true
		if event.pressed and track.rotary_drag_enabled and not dragging:
			var offset: Vector2 = get_viewport().canvas_transform.affine_inverse() * event.position - track.get_track_center_global()
			var distance := offset.length()
			if not Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).has_point(event.position):
				return false
			if distance < track.rotary_hub_radius_pixels or distance > track.rotary_grab_radius_pixels:
				return false
			cancel_return()
			dragging = true
			rest_rotation = track.rotation
			pointer_angle = offset.angle()
			return true
	if event is InputEventMouseMotion and dragging:
		var next_angle: float = (get_viewport().canvas_transform.affine_inverse() * event.position - track.get_track_center_global()).angle()
		track.rotation += angle_difference(pointer_angle, next_angle)
		pointer_angle = next_angle
		track.relayout_slots()
		return true
	return false

func return_duration() -> float:
	if not is_instance_valid(track):
		return 0.0
	var distance := absf(rest_rotation - track.rotation)
	return track.snap_back_duration_seconds if track.snap_back_fixed_duration else track.snap_back_duration_seconds * distance / PI

func begin_return() -> void:
	if not track.snap_back_on_release:
		return
	if track.snap_back_duration_seconds <= 0.0:
		track.rotation = rest_rotation
		track.relayout_slots()
		return
	if absf(rest_rotation - track.rotation) < deg_to_rad(track.snap_back_dead_zone_degrees):
		return
	snap_tween = create_tween()
	snap_tween.tween_property(track, "rotation", rest_rotation, return_duration())
	snap_tween.finished.connect(func():
		snap_tween = null
		if is_instance_valid(track):
			track.relayout_slots()
	)

func cancel_return() -> void:
	if snap_tween != null:
		snap_tween.kill()
	snap_tween = null

func cancel_pointer() -> void:
	dragging = false
	cancel_return()

func stop() -> void:
	playing = false
	cancel_pointer()
	if is_instance_valid(track):
		track.preview_stop()
		track.rotation = 0.0
		track.relayout_slots()

func _exit_tree() -> void:
	stop()
	track = null
