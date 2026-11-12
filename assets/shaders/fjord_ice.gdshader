// Frozen fjord: glossy blue-white ice with cracks and pressure ridges.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform vec3 ice_a : source_color = vec3(0.7, 0.82, 0.92);
uniform vec3 ice_b : source_color = vec3(0.35, 0.55, 0.72);

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float n = vnoise(p * 0.01) * 0.6 + vnoise(p * 0.05) * 0.4;
	// Cracks: thin lines where a cellular-ish pattern changes.
	vec2 g = p / 40.0;
	vec2 f = fract(g) - 0.5;
	float crack = 1.0 - smoothstep(0.0, 0.025 + fwidth(g.x) * 1.5, min(abs(f.x + (vnoise(g * 3.0) - 0.5) * 0.3), abs(f.y + (vnoise(g * 3.1 + 7.0) - 0.5) * 0.3)));
	vec2 w = fwidth(p);
	float fade = clamp(1.0 - length(w) * 0.02, 0.0, 1.0);
	ALBEDO = mix(ice_b, ice_a, n) * (1.0 - crack * 0.5 * fade);
	ROUGHNESS = 0.12 + crack * 0.4;
	SPECULAR = 0.7;
	METALLIC = 0.0;
}
