// Glacier ice seen from inside the Crevasse Tunnel: glowing deep blue with
// lighter veins, as if lit through the ice. UV.y = height around the arch.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

uniform vec3 deep : source_color = vec3(0.02, 0.12, 0.28);
uniform vec3 bright : source_color = vec3(0.35, 0.8, 1.0);

varying vec3 wpos;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = noise(wpos * 0.15) * 0.6 + noise(wpos * 0.6) * 0.4;
	float vein = smoothstep(0.62, 0.7, noise(wpos * vec3(0.08, 0.3, 0.08)));
	ALBEDO = mix(deep, bright * 0.6, n * 0.5);
	ROUGHNESS = 0.15;
	SPECULAR = 0.6;
	EMISSION = mix(deep, bright, n * 0.6 + vein * 0.6) * (0.6 + 0.6 * n);
}
