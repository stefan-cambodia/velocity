// Harbour water at dusk: dark, glossy, with moving ripples. The sky colour is
// reflected through a Fresnel term; streaks of warm light imitate the city's
// reflections near the horizon.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, specular_schlick_ggx;

uniform vec3 deep : source_color = vec3(0.01, 0.02, 0.04);
uniform vec3 shallow : source_color = vec3(0.02, 0.06, 0.08);
uniform vec3 reflect_col : source_color = vec3(0.6, 0.32, 0.4);
uniform vec3 glints : source_color = vec3(1.0, 0.6, 0.3);
uniform float ripple = 1.0;   // ripple frequency multiplier (1 = harbour scale)
uniform float chop = 1.0;     // normal strength of the ripples

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
	vec2 p = wpos.xz * ripple;
	float t = TIME;
	float h1 = vnoise(p * 0.06 + vec2(t * 0.05, t * 0.03));
	float h2 = vnoise(p * 0.21 - vec2(t * 0.11, -t * 0.07));
	float h3 = vnoise(p * 0.7 + vec2(t * 0.3, t * 0.21));
	float hx = (vnoise(p * 0.21 + vec2(0.7, 0.0) - vec2(t * 0.11, -t * 0.07)) - h2);
	float hz = (vnoise(p * 0.21 + vec2(0.0, 0.7) - vec2(t * 0.11, -t * 0.07)) - h2);
	vec3 n = normalize(vec3((hx * 0.6 + (h1 - 0.5) * 0.1) * chop, 1.0, (hz * 0.6 + (h3 - 0.5) * 0.1) * chop));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = mix(deep, shallow, h1 * 0.5);
	ROUGHNESS = 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	// Reflected sky plus broken light streaks.
	float streak = smoothstep(0.62, 0.95, vnoise(vec2(p.x * 0.02, p.y * 0.4) + h2));
	EMISSION = reflect_col * fres * 0.9 + glints * streak * fres * 0.6;
}
