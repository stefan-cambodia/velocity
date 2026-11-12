// Speed pad: glowing chevrons scrolling in the direction of travel.
// UV.x across (0..1), UV.y along (0 = entry .. 1 = exit).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

uniform vec3 color : source_color = vec3(0.2, 0.75, 1.0);
uniform float energy = 3.0;

void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;
	float ph = fract(UV.y * 4.0 - x * 0.6 - TIME * 3.0);
	float chev = smoothstep(0.0, 0.08, ph) * (1.0 - smoothstep(0.35, 0.45, ph));
	float frame = max(step(0.92, x), step(0.96, abs(UV.y - 0.5) * 2.0));
	vec3 base = vec3(0.02, 0.03, 0.05);
	ALBEDO = base + color * energy * max(chev * (1.0 - x * 0.4), frame * 0.7);
}
