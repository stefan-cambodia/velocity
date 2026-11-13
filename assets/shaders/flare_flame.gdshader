// Gas flare flames (Tempest Shoals): crossed vertical quads, additive. UV.x runs
// 0..1 across a quad, UV.y 0 at the burner .. 1 at the tip. COLOR.g is a
// per-flame random offset so neighbouring flares do not flicker in step.
// The tongue shape is cut from the baked cloud texture scrolling upward.
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 hot : source_color = vec3(1.0, 0.86, 0.5);
uniform vec3 cool : source_color = vec3(1.0, 0.32, 0.04);
uniform float energy = 3.5;

void fragment() {
	float t = TIME;
	float r = COLOR.g;
	vec2 q = vec2(UV.x * 0.35 + r * 7.0, UV.y * 0.45 - t * 0.9);
	float n1 = texture(noise_tex, q).g;
	float n2 = texture(noise_tex, q * 2.3 + vec2(r, -t * 0.5)).r;
	float x = abs(UV.x - 0.5) * 2.0 + (n1 - 0.5) * 0.7 * UV.y;
	float width = mix(0.85, 0.12, UV.y);
	float body = 1.0 - smoothstep(width * 0.45, width, x);
	float tip = 1.0 - smoothstep(0.45, 1.0, UV.y + (n2 - 0.5) * 0.5);
	float shape = body * tip * smoothstep(0.0, 0.05, UV.y);
	vec3 c = mix(hot, cool, smoothstep(0.05, 0.75, UV.y + (n1 - 0.5) * 0.3));
	float flicker = 0.82 + 0.18 * sin(t * 17.0 + r * 40.0) * sin(t * 7.3 + r * 13.0);
	ALBEDO = c * shape * energy * flicker;
}
