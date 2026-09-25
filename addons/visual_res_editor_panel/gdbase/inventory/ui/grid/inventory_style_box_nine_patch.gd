class_name InventoryStyleBoxNinePatch
extends RefCounted
## 将 StyleBox 配置映射到 NinePatchRect。
## StyleBoxTexture 写入贴图、裁切、九宫格边距与调色；关闭绘制、空样式或非纹理样式时清空贴图并复位调色。


## 按开关与样式配置目标九宫格。
static func apply(
	target: NinePatchRect,
	configured_style: StyleBox,
	show_background: bool
) -> void:
	if target == null:
		return
	if not show_background or configured_style == null:
		clear(target)
		return
	if configured_style is StyleBoxTexture:
		var texture_style := configured_style as StyleBoxTexture
		target.texture = texture_style.texture
		target.region_rect = texture_style.region_rect
		target.patch_margin_left = int(texture_style.texture_margin_left)
		target.patch_margin_top = int(texture_style.texture_margin_top)
		target.patch_margin_right = int(texture_style.texture_margin_right)
		target.patch_margin_bottom = int(texture_style.texture_margin_bottom)
		# StyleBoxTexture 调色对应九宫格 modulate；悬停等仍可用 self_modulate 叠加。
		target.modulate = texture_style.modulate_color
		return
	clear(target)


## 清空九宫格贴图与调色，显示为透明占位。
static func clear(target: NinePatchRect) -> void:
	if target == null:
		return
	target.texture = null
	target.region_rect = Rect2()
	target.patch_margin_left = 0
	target.patch_margin_top = 0
	target.patch_margin_right = 0
	target.patch_margin_bottom = 0
	target.modulate = Color.WHITE
