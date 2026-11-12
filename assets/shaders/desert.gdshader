// High desert: white salt crust on the flats (polygon cracks), red-brown sand,
// and stratified rock (horizontal bands) on steep faces.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 salt : source_color = vec3(0.93, 0.92, 0.88);
uniform vec3 sand : source_color = vec3(0.72, 0.45, 0.3);
uniform vec3 rock_a : source_color = vec3(0.55, 0.26, 0.16);
uniform vec3 rock_b : source_color = vec3(0.78, 0.5, 0.32);
uniform float salt_level = 2.2;

varying vec3 wpos;
varying vec3 wn;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// Distance to the nearest edge of a jittered cell pattern (salt polygons).
float cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(i + g), hash(i + g + 17.0));
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	}
	return d2 - d1;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);
	float n = vnoise(wpos.xz * 0.02) * 0.6 + vnoise(wpos.xz * 0.11) * 0.4;
	vec2 w0 = fwidth(wpos.xz);
	float detail = clamp(1.0 - length(w0) * 0.6, 0.0, 1.0);
	// Wind ripples in the sand (fade out before they alias).
	float ripple = sin(dot(wpos.xz, vec2(0.83, 0.55)) * 2.2 + vnoise(wpos.xz * 0.15) * 6.0) * 0.5 + 0.5;
	float grain = vnoise(wpos.xz * 1.7);
	vec3 ground = mix(sand * 0.8, sand * 1.12, n) * (1.0 - 0.12 * ripple * detail) * (0.94 + 0.12 * grain * detail);
	// Salt crust on the low flats, with polygon cracks that fade with distance.
	float salty = (1.0 - smoothstep(salt_level - 1.0, salt_level + 0.8, wpos.y + n * 1.5)) * (1.0 - smoothstep(0.08, 0.2, slope));
	vec2 w = fwidth(wpos.xz);
	float fade = clamp(1.0 - length(w) * 0.25, 0.0, 1.0);
	float crack = (1.0 - smoothstep(0.02, 0.08, cells(wpos.xz * 0.35))) * fade;
	vec3 saltc = salt * (1.0 - crack * 0.35) * (0.95 + 0.05 * n);
	vec3 col = mix(ground, saltc, salty);
	// Rock strata on steep faces.
	float rocky = smoothstep(0.14, 0.28, slope);
	float band = sin(wpos.y * 0.9 + n * 3.0) * 0.5 + 0.5;
	float seam = smoothstep(0.92, 0.99, sin(wpos.y * 0.45 + n * 2.0) * 0.5 + 0.5);
	vec3 rock = mix(rock_a, rock_b, band) * (0.85 + 0.3 * n) * (1.0 - seam * 0.45) * (0.9 + 0.2 * grain * detail);
	col = mix(col, rock, rocky);
	ALBEDO = col;
	ROUGHNESS = mix(0.9, 0.55, salty);
	SPECULAR = mix(0.3, 0.5, salty);
}
