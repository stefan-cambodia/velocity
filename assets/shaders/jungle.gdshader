// Rainforest terrain: a canopy of tree crowns on gentle ground, wet mossy rock
// with run-off streaks on steep faces, and red clay banks along the water.
// Crown and streak detail fade with distance before they alias.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 canopy_a : source_color = vec3(0.05, 0.16, 0.04);
uniform vec3 canopy_b : source_color = vec3(0.17, 0.34, 0.07);
uniform vec3 bloom : source_color = vec3(0.62, 0.52, 0.12);
uniform vec3 rock_a : source_color = vec3(0.14, 0.15, 0.13);
uniform vec3 moss : source_color = vec3(0.1, 0.17, 0.06);
uniform vec3 clay : source_color = vec3(0.36, 0.2, 0.11);
uniform float water_y = 2.0;

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

// Distance from the nearest jittered cell centre (tree crowns), and that cell's id.
vec2 crowns(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(i + g), hash(i + g + 17.0)) * 0.8 + 0.1;
			float d = length(g + o - f);
			if (d < d1) { d1 = d; id = hash(i + g + 3.1); }
		}
	}
	return vec2(d1, id);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);
	float n = vnoise(wpos.xz * 0.012) * 0.6 + vnoise(wpos.xz * 0.06) * 0.4;
	vec2 w = fwidth(wpos.xz);
	float fade = clamp(1.0 - length(w) * 0.12, 0.0, 1.0);
	// Canopy: rounded crowns about 10 m across, each a slightly different green,
	// the odd one in flower.
	vec3 canopy = mix(canopy_a, canopy_b, n);
	// Crowns are laid out in plan, so they would smear on slopes: flat ground only.
	float flat_k = fade * (1.0 - smoothstep(0.08, 0.2, slope));
	if (flat_k > 0.0) {
		vec2 c = crowns(wpos.xz * 0.1);
		float dome = 1.0 - smoothstep(0.15, 0.75, c.x);
		vec3 tree = mix(canopy_a, canopy_b, c.y) * (0.55 + 0.7 * dome);
		tree = mix(tree, bloom * (0.6 + 0.6 * dome), step(0.985, c.y));
		canopy = mix(canopy, tree, flat_k);
	}
	// Steep faces: dark wet rock, moss in patches, vertical run-off streaks.
	float rocky = smoothstep(0.32, 0.52, slope + (n - 0.5) * 0.25);
	float streak = vnoise(vec2((wpos.x + wpos.z) * 0.35, wpos.y * 0.04));
	vec3 rock = mix(rock_a, moss, smoothstep(0.45, 0.7, vnoise(wpos.xz * 0.05 + wpos.y * 0.04)));
	rock *= mix(1.0, 0.7 + 0.6 * streak, fade);
	// Clay banks just above the waterline.
	float bank = 1.0 - smoothstep(water_y + 0.8, water_y + 3.0, wpos.y + n * 1.5);
	vec3 col = mix(canopy, rock, rocky);
	col = mix(col, clay * (0.75 + 0.5 * n), bank * (1.0 - rocky * 0.6));
	ALBEDO = col;
	ROUGHNESS = mix(0.88, 0.32, max(rocky, bank * 0.5));
	SPECULAR = mix(0.22, 0.5, rocky);
}
