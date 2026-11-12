// Exhaust plume: additive, unshaded, scrolling noise along the length.
// UV.y = 0 at the nozzle .. 1 at the tip; UV.x around. `thrust` per instance.
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec3 hot : source_color = vec3(1.0, 0.95, 0.85);
uniform vec3 cool : source_color = vec3(1.0, 0.38, 0.08);
uniform float energy = 1.5;
instance uniform float thrust = 1.0;
instance uniform vec4 plume_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float v = UV.y;
	float n = vnoise(vec2(UV.x * 6.0, v * 5.0 - TIME * 24.0)) * 0.6 + vnoise(vec2(UV.x * 13.0, v * 11.0 - TIME * 41.0)) * 0.4;
	float len_fade = pow(clamp(1.0 - v, 0.0, 1.0), 1.6);
	// Fresnel-like edge softening: plume is a cone, fade where it is seen edge-on.
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float edge = smoothstep(0.0, 0.6, facing);
	float a = len_fade * edge * (0.55 + 0.45 * n) * clamp(thrust, 0.0, 1.6);
	vec3 c = mix(cool, hot, clamp(1.0 - v * 1.6, 0.0, 1.0)) * plume_tint.rgb;
	ALBEDO = c * a * energy;
}
