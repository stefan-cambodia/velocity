// Blinking obstruction lights (wind turbines, cranes, flare stacks). COLOR.r is
// a phase offset in cycles: lights that share it blink in step, as a wind farm's
// do. Unshaded and emissive, so the glow pass makes the halo.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded, shadows_disabled;

uniform vec3 color : source_color = vec3(1.0, 0.05, 0.03);
uniform float energy = 7.0;
uniform float period = 2.0;
uniform float duty = 0.3;

void fragment() {
	float ph = fract(TIME / period + COLOR.r);
	float on = 1.0 - smoothstep(duty, duty + 0.06, ph);
	ALBEDO = color * energy * mix(0.04, 1.0, on);
}
