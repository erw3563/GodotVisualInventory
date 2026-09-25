shader_type canvas_item;
render_mode unshaded;

// ---------- 颜色 ----------
group_uniforms Colors;

// 默认采用接近参考视频的浅米色与橙色。
uniform vec4 color_a : source_color = vec4(0.98, 0.86, 0.73, 1.0);
uniform vec4 color_b : source_color = vec4(0.96, 0.77, 0.54, 1.0);

// ---------- 图案布局 ----------
group_uniforms Pattern;

// 基础格子的边长，单位为控件局部像素。
uniform float cell_size : hint_range(8.0, 512.0, 1.0) = 160.0;

// 大于 1 放大图案，小于 1 缩小图案。
uniform float pattern_scale : hint_range(0.1, 8.0, 0.01) = 1.0;

// 图案整体旋转角度，单位为度，绕控件局部原点旋转。
uniform float rotation_degrees : hint_range(-180.0, 180.0, 0.1) = 18.0;

// 图案偏移，单位为基础格；方向沿旋转后的图案坐标轴。
uniform vec2 uv_offset = vec2(0.0);

// 自动平移速度，单位为基础格 / 秒。默认不平移。
uniform vec2 scroll_speed = vec2(0.0);

// ---------- 动画 ----------
group_uniforms Animation;

// true：由 TIME 自动播放。
// false：不使用 TIME，画面由 phase 和 uv_offset 决定。
// 注意：关闭自动播放不等于保留关闭瞬间的相位。
uniform bool animate = true;

// 完整循环次数 / 秒。0.5 表示 2 秒完成一次循环。
uniform float speed : hint_range(0.0, 4.0, 0.01) = 0.5;

// 相位：0 和 1 是同一帧，可由脚本或 Tween 驱动。
uniform float phase : hint_range(0.0, 1.0, 0.001) = 0.0;

// 变化幅度：1 为完整变形，0 为初始静态图案。
uniform float deformation : hint_range(0.0, 1.0, 0.01) = 1.0;

// ---------- 边缘 ----------
group_uniforms Quality;

// 抗锯齿强度。1 为正常，0 接近硬边。
uniform float antialias : hint_range(0.0, 2.0, 0.1) = 1.0;

group_uniforms;

varying vec2 local_position_px;
varying vec4 vertex_tint;


// 显式计算旋转，不需要构造矩阵。
vec2 rotate_point(vec2 point, float angle) {
	float c = cos(angle);
	float s = sin(angle);

	return vec2(
		c * point.x - s * point.y,
		s * point.x + c * point.y
	);
}


void vertex() {
	// 使用局部像素坐标，避免控件宽高变化导致格子比例失真。
	local_position_px = VERTEX;

	// 保留 ColorRect.color、modulate 和 self_modulate 的影响。
	vertex_tint = COLOR;
}


void fragment() {
	float animation_time = animate ? TIME : 0.0;

	// 1. 构造图案坐标：一个坐标单位就是一个基础格。
	float size_px = max(cell_size * pattern_scale, 1.0);
	vec2 p = local_position_px / size_px;

	// 反向变换采样坐标，使正角度表现为图案顺时针旋转。
	p = rotate_point(p, -radians(rotation_degrees));
	p -= uv_offset + scroll_speed * animation_time;

	// 2. 循环变形量：0 -> 1 -> 0，首尾连续。
	float cycle = fract(animation_time * speed + phase);
	float morph = 0.5 - 0.5 * cos(TAU * cycle);
	morph *= clamp(deformation, 0.0, 1.0);

	// 3. 将格子分成两类，交错排列。
	vec2 cell_id = floor(p);
	vec2 cell_uv = fract(p) - vec2(0.5);
	float parity = mod(cell_id.x + cell_id.y, 2.0);

	// 偶数格：收缩包含两块三角形的方形区域。
	// 奇数格：扩大中心的反色方形。
	float radius = 0.5 * mix(1.0 - morph, morph, parity);

	// 4. 在连续坐标上计算导数，不对 floor / fract 的跳变求导。
	vec2 footprint = fwidth(p);
	float edge_scale = 0.5 * max(antialias, 0.0);

	float box_aa = max(
		max(footprint.x, footprint.y) * edge_scale,
		0.00001
	);

	float stripe_aa = max(
		fwidth(p.x - p.y) * edge_scale,
		0.00001
	);

	// 5. 连续的对角双色带，提供所有格子共享的底层分界。
	float stripe_distance =
		abs(mod(p.x - p.y + 1.0, 4.0) - 2.0) - 1.0;

	float base_mask = smoothstep(
		-stripe_aa,
		stripe_aa,
		stripe_distance
	);

	// 6. 计算每格中心的动态方形区域。
	float box_distance =
		max(abs(cell_uv.x), abs(cell_uv.y)) - radius;

	float box_mask = 1.0 - smoothstep(
		-box_aa,
		box_aa,
		box_distance
	);

	// 半径归零时完全消失，避免中心残留一个抗锯齿亮点。
	box_mask *= smoothstep(0.0, box_aa, radius);

	// 7. 在动态方形内交换两色。
	// 方形与对角分界相交，形成同步缩放的三角形与中心方形。
	float pattern_mask = mix(
		base_mask,
		1.0 - base_mask,
		box_mask
	);

	COLOR = mix(color_a, color_b, pattern_mask) * vertex_tint;
}
