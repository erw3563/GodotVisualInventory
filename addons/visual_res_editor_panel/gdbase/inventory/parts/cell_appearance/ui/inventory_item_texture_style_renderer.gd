@tool
class_name InventoryItemTextureStyleRenderer
extends InventoryItemStyleRenderer
## 使用当前样式的贴图与边距创建独占九宫格节点。
const SIDE_TOP := 1
const SIDE_RIGHT := 2
const SIDE_BOTTOM := 4
const SIDE_LEFT := 8
var inventory_grid_panel: InventoryGridPanel
var frame_texture: Texture2D
var fill_texture: Texture2D
var frame_border_margins: Vector4i

func _accept_style(value: InventoryItemVisualStyle) -> bool:
	return value is InventoryItemTextureVisualStyle

func _render() -> void:
	inventory_grid_panel = context.grid
	var texture_style := style as InventoryItemTextureVisualStyle
	frame_texture = texture_style.frame_texture
	fill_texture = texture_style.fill_texture
	frame_border_margins = texture_style.frame_border_margins
	_build_fill_nodes(fill_cells, context.fill_parent, style.fill_color)
	if border_cells.is_empty():
		return
	var lookup := {}
	for cell in border_cells:
		lookup[cell] = true
	_build_frame_nine_patches(border_cells, lookup, context.border_parent, style.border_color)

## 创建填充节点（每个格子一张）。
func _build_fill_nodes(target_cells: Array[Vector2i], target_container: Control, fill_color: Color) -> void:
	for target_cell in target_cells:
		var cell_position := inventory_grid_panel.get_cell_local_position(target_cell)
		var cell_size := inventory_grid_panel.cell_size
		var fill_node: Control
		if fill_texture == null:
			var fill_color_rect := ColorRect.new()
			fill_color_rect.color = fill_color
			fill_node = fill_color_rect
		else:
			var fill_patch := NinePatchRect.new()
			_configure_fill_nine_patch(fill_patch, cell_size)
			fill_patch.modulate = fill_color
			fill_node = fill_patch
		fill_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill_node.position = cell_position
		fill_node.size = cell_size
		own_drawing(fill_node, target_container)

## 为暴露边创建 NinePatchRect 边框条。
func _build_frame_nine_patches(
	target_cells: Array[Vector2i],
	cell_lookup: Dictionary,
	target_container: Control,
	frame_color: Color
) -> void:
	var source_rect := _get_frame_source_rect()
	var scale := _get_frame_display_scale(source_rect)
	for target_cell in target_cells:
		var side_mask := _get_exposed_side_mask(target_cell, cell_lookup)
		if side_mask == 0:
			continue
		var cell_position := inventory_grid_panel.get_cell_local_position(target_cell)
		var cell_size := inventory_grid_panel.cell_size
		for side_flag in [SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM, SIDE_LEFT]:
			if side_mask & side_flag == 0:
				continue
			var frame_patch := NinePatchRect.new()
			frame_patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
			frame_patch.modulate = frame_color
			frame_patch.draw_center = false
			_configure_edge_nine_patch(frame_patch, side_flag, source_rect, cell_position, cell_size, scale)
			own_drawing(frame_patch, target_container)

## 配置填充用 NinePatchRect（使用源图中心区域）。
func _configure_fill_nine_patch(target_patch: NinePatchRect, _cell_size: Vector2) -> void:
	target_patch.texture = fill_texture.atlas if fill_texture is AtlasTexture else fill_texture
	var source_rect := _get_fill_source_rect()
	target_patch.region_rect = source_rect
	target_patch.patch_margin_left = frame_border_margins.x
	target_patch.patch_margin_top = frame_border_margins.y
	target_patch.patch_margin_right = frame_border_margins.z
	target_patch.patch_margin_bottom = frame_border_margins.w
	target_patch.draw_center = true

## 按边方向配置 NinePatchRect 的 region_rect、尺寸与 patch_margin。
func _configure_edge_nine_patch(
	target_patch: NinePatchRect,
	side_flag: int,
	source_rect: Rect2,
	cell_position: Vector2,
	cell_size: Vector2,
	display_scale: Vector2
) -> void:
	target_patch.texture = frame_texture.atlas if frame_texture is AtlasTexture else frame_texture
	var margin_left := frame_border_margins.x
	var margin_top := frame_border_margins.y
	var margin_right := frame_border_margins.z
	var margin_bottom := frame_border_margins.w
	var display_margin_left := float(margin_left) * display_scale.x
	var display_margin_top := float(margin_top) * display_scale.y
	var display_margin_right := float(margin_right) * display_scale.x
	var display_margin_bottom := float(margin_bottom) * display_scale.y
	match side_flag:
		SIDE_TOP:
			target_patch.position = cell_position
			target_patch.size = Vector2(cell_size.x, display_margin_top)
			target_patch.region_rect = Rect2(
				source_rect.position.x,
				source_rect.position.y,
				source_rect.size.x,
				margin_top
			)
			target_patch.patch_margin_left = margin_left
			target_patch.patch_margin_top = margin_top
			target_patch.patch_margin_right = margin_right
			target_patch.patch_margin_bottom = 0
		SIDE_RIGHT:
			target_patch.position = cell_position + Vector2(cell_size.x - display_margin_right, 0.0)
			target_patch.size = Vector2(display_margin_right, cell_size.y)
			target_patch.region_rect = Rect2(
				source_rect.position.x + source_rect.size.x - margin_right,
				source_rect.position.y,
				margin_right,
				source_rect.size.y
			)
			target_patch.patch_margin_left = margin_right
			target_patch.patch_margin_top = margin_top
			target_patch.patch_margin_right = 0
			target_patch.patch_margin_bottom = margin_bottom
		SIDE_BOTTOM:
			target_patch.position = cell_position + Vector2(0.0, cell_size.y - display_margin_bottom)
			target_patch.size = Vector2(cell_size.x, display_margin_bottom)
			target_patch.region_rect = Rect2(
				source_rect.position.x,
				source_rect.position.y + source_rect.size.y - margin_bottom,
				source_rect.size.x,
				margin_bottom
			)
			target_patch.patch_margin_left = margin_left
			target_patch.patch_margin_top = 0
			target_patch.patch_margin_right = margin_right
			target_patch.patch_margin_bottom = margin_bottom
		SIDE_LEFT:
			target_patch.position = cell_position
			target_patch.size = Vector2(display_margin_left, cell_size.y)
			target_patch.region_rect = Rect2(
				source_rect.position.x,
				source_rect.position.y,
				margin_left,
				source_rect.size.y
			)
			target_patch.patch_margin_left = margin_left
			target_patch.patch_margin_top = margin_top
			target_patch.patch_margin_right = 0
			target_patch.patch_margin_bottom = margin_bottom

## 获取边框源图在贴图坐标系中的矩形。
func _get_frame_source_rect() -> Rect2:
	if frame_texture is AtlasTexture:
		return _atlas_region(frame_texture)
	return Rect2(0.0, 0.0, frame_texture.get_width(), frame_texture.get_height())

## 获取填充源图在贴图坐标系中的矩形。
func _get_fill_source_rect() -> Rect2:
	if fill_texture is AtlasTexture:
		return _atlas_region(fill_texture)
	return Rect2(0.0, 0.0, fill_texture.get_width(), fill_texture.get_height())

## 源图尺寸映射到格子显示时的缩放比。
func _get_frame_display_scale(source_rect: Rect2) -> Vector2:
	if source_rect.size.x <= 0.0 or source_rect.size.y <= 0.0:
		return Vector2.ONE
	var cell_size := inventory_grid_panel.cell_size
	return Vector2(cell_size.x / source_rect.size.x, cell_size.y / source_rect.size.y)

## 获取当前格子暴露出的边框方向。
func _get_exposed_side_mask(target_cell: Vector2i, cell_lookup: Dictionary) -> int:
	var side_mask := 0
	var top_cell := target_cell + Vector2i(0, -1)
	var right_cell := target_cell + Vector2i(1, 0)
	var bottom_cell := target_cell + Vector2i(0, 1)
	var left_cell := target_cell + Vector2i(-1, 0)
	if !_lookup_has_cell(cell_lookup, top_cell):
		side_mask |= SIDE_TOP
	if !_lookup_has_cell(cell_lookup, right_cell):
		side_mask |= SIDE_RIGHT
	if !_lookup_has_cell(cell_lookup, bottom_cell):
		side_mask |= SIDE_BOTTOM
	if !_lookup_has_cell(cell_lookup, left_cell):
		side_mask |= SIDE_LEFT
	return side_mask

## 判断格子是否存在于查找表中。
func _lookup_has_cell(cell_lookup: Dictionary, cell_index: Vector2i) -> bool:
	return cell_lookup.has(cell_index)

func _atlas_region(texture: AtlasTexture) -> Rect2:
	var region := texture.region
	if region.size == Vector2.ZERO:
		region.size = texture.atlas.get_size()
	return region
