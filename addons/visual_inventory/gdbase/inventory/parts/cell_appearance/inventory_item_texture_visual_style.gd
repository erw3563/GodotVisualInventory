@tool
class_name InventoryItemTextureVisualStyle
extends InventoryItemVisualStyle
## 按暴露边拼接框图，并按占格绘制填充图或纯色。
@export var frame_texture: Texture2D
@export var fill_texture: Texture2D
@export var frame_border_margins := Vector4i(6, 6, 6, 6)

func _validate_style() -> StringName:
	if use_border:
		if frame_texture == null:
			return &"appearance_frame_texture_missing"
		if not _valid_patch(frame_texture):
			return &"appearance_frame_margins_invalid"
	if use_fill and fill_texture != null and not _valid_patch(fill_texture):
		return &"appearance_fill_texture_invalid"
	return &""

func _valid_patch(texture: Texture2D) -> bool:
	var dimensions := texture.get_size()
	if texture is AtlasTexture:
		if texture.atlas == null:
			return false
		var region: Rect2 = texture.region
		if region.size == Vector2.ZERO:
			region.size = texture.atlas.get_size()
		if not Rect2(Vector2.ZERO, texture.atlas.get_size()).encloses(region):
			return false
		dimensions = region.size
	var margins := frame_border_margins
	return margins.x > 0 and margins.y > 0 and margins.z > 0 and margins.w > 0 and margins.x + margins.z < dimensions.x and margins.y + margins.w < dimensions.y

func create_renderer() -> InventoryItemStyleRenderer:
	return InventoryItemTextureStyleRenderer.new()
