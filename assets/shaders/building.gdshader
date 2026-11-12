// Tower facades with procedural night windows. UV = facade coordinates in
// metres (u along the face, v up). COLOR.rgb = facade tint, COLOR.a = window
// style (0 = no windows (roofs, plinths), 0.5 = office grid, 1 = residential).
// Windows average out to their mean brightness with distance, so far towers
// shimmer neither on desktop nor on a phone.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 warm : source_color = vec3(1.0, 0.72, 0.42);
uniform vec3 cool : source_color = vec3(0.55, 0.78, 1.0);
uniform float window_energy = 1.35;
uniform float lit_fraction = 0.34;      // kept for compatibility (pattern is in the texture)
uniform float floor_h = 3.3;
uniform float bay_w = 1.7;
uniform sampler2D windows_tex : filter_linear_mipmap, repeat_enable;

varying vec3 wn;

void vertex() {
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

void fragment() {
	vec3 tint = COLOR.rgb * 0.5;
	float style = COLOR.a;
	// Style 0.25..0.75 = office, 0.75..1 = residential; the fraction within a
	// band is a per-building random offset into the window pattern.
	float has_windows = step(0.25, style) * step(abs(normalize(wn).y), 0.5);
	float rnd = fract(style * 4.0);
	vec2 cell_uv = UV / vec2(bay_w * 32.0, floor_h * 32.0) + vec2(rnd * 0.53, rnd * 0.71);
	vec4 w = texture(windows_tex, cell_uv);
	vec3 wcol = mix(cool, warm, w.g);
	float pane = w.b * has_windows;
	ALBEDO = mix(tint, vec3(0.03, 0.04, 0.06), pane * 0.85);
	ROUGHNESS = mix(0.75, 0.2, pane);
	METALLIC = 0.2;
	EMISSION = wcol * w.r * has_windows * window_energy * (lit_fraction / 0.34);
}
