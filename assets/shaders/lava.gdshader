// Molten lava: dark crust plates drifting over a glowing melt, bright cracks
// between the plates and hot upwellings. Unshaded (it is the light source).
// flow = 0: lake, in world XZ, slow drift. flow = 1: river or pour, along UV
// (UV.x 0..1 across, UV.y = metres along / 10), streaming downhill.
// All noise from the baked forge_noise texture (two lookups).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded, shadows_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 hot : source_color = vec3(1.0, 0.62, 0.18);
uniform vec3 warm : source_color = vec3(0.95, 0.2, 0.03);
uniform vec3 crust : source_color = vec3(0.045, 0.02, 0.016);
uniform float energy = 3.2;
uniform float flow = 0.0;
uniform float speed = 1.0;
uniform float crust_amount = 0.55;   // 0 = all molten, 1 = mostly crust

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME * speed;
	vec2 lake = wpos.xz * 0.008 + vec2(t * 0.003, t * 0.002);
	vec2 river = vec2(UV.x * 0.35, UV.y * 0.18 - t * 0.09);
	vec2 p = mix(lake, river, flow);
	// Low-frequency field: where the crust is thick or broken, and the warp.
	vec4 b = texture(noise_tex, p * 0.29 + vec2(-t * 0.002, t * 0.0015) * (1.0 - flow) + vec2(0.0, -t * 0.03) * flow);
	vec2 warp = (b.rb - 0.5) * 0.4;
	vec4 a = texture(noise_tex, p + warp);
	vec4 a2 = texture(noise_tex, p * 2.7 + warp * 1.7 + vec2(0.41, 0.23));
	// Plates with molten seams. Seam width and the small plates vary over the
	// surface, so the net never reads as a regular tiling.
	float thick = clamp(crust_amount + (b.r - 0.5) * 0.8, 0.0, 1.0);
	float seam = 1.0 - smoothstep(0.0, mix(0.3, 0.06, thick), a.g + (a2.r - 0.5) * 0.18);
	float seam2 = (1.0 - smoothstep(0.0, mix(0.22, 0.04, thick), a2.g)) * (1.0 - thick) * 0.8;
	float well = smoothstep(0.66, 0.9, b.b) * (0.6 + 0.4 * a2.r);
	float melt = clamp(max(seam, seam2) + well + (1.0 - thick) * 0.35 * a.r, 0.0, 1.0);
	// River edges stay crusted and darker.
	float edge = mix(1.0, smoothstep(0.0, 0.22, UV.x) * smoothstep(1.0, 0.78, UV.x), flow);
	melt *= mix(0.55, 1.0, edge);
	vec3 c = crust * (0.6 + 0.9 * a.a);
	c = mix(c, warm, smoothstep(0.08, 0.55, melt));
	c = mix(c, hot, smoothstep(0.55, 1.0, melt));
	ALBEDO = c * energy;
}
