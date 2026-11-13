// Thalassa Deep seabed: rippled sand on the shelf, dark silt in the deep,
// rock on steep faces, animated caustics on up-facing ground (two scrolling
// layers of the baked network, minimum of the two) fading with depth, and
// bioluminescent specks that pulse on the floor and walls of the deep. All
// detail fades with screen-space footprint so it does not alias on a phone.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D tex : filter_linear_mipmap, repeat_enable;
uniform vec3 sand_a : source_color = vec3(0.6, 0.56, 0.45);
uniform vec3 sand_b : source_color = vec3(0.44, 0.44, 0.38);
uniform vec3 silt : source_color = vec3(0.16, 0.19, 0.22);
uniform vec3 rock_a : source_color = vec3(0.2, 0.21, 0.21);
uniform vec3 rock_deep : source_color = vec3(0.09, 0.1, 0.13);
uniform vec3 caustic_col : source_color = vec3(0.7, 1.0, 0.92);
uniform vec3 glow_a : source_color = vec3(0.1, 0.95, 1.0);
uniform vec3 glow_b : source_color = vec3(0.75, 0.25, 1.0);
uniform float shelf_y = 0.0;
uniform float deep_y = -50.0;
uniform float caustic_energy = 2.2;
uniform float glow_energy = 2.5;

varying vec3 wpos;
varying vec3 wn;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.31, 289.17))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float up = clamp(wn.y, 0.0, 1.0);
	float slope = 1.0 - up;
	float depth = clamp((shelf_y - wpos.y) / (shelf_y - deep_y), 0.0, 1.0);
	float fade = clamp(1.0 - length(fwidth(wpos.xz)) * 0.18, 0.0, 1.0);
	vec4 big = texture(tex, wpos.xz * 0.0045);
	vec4 small = texture(tex, wpos.xz * 0.035);
	// Sand: mottled, with ripple crests up close.
	vec3 sand = mix(sand_a, sand_b, big.b) * mix(1.0, 0.8 + 0.4 * small.a, fade);
	sand = mix(sand, silt * (0.8 + 0.4 * big.b), smoothstep(0.15, 0.75, depth));
	// Rock on steep faces, banded vertically.
	float rocky = smoothstep(0.32, 0.6, slope + (big.b - 0.5) * 0.3);
	float band = texture(tex, vec2((wpos.x + wpos.z) * 0.01, wpos.y * 0.05)).b;
	vec3 rock = mix(rock_a, rock_deep, depth) * (0.65 + 0.7 * band);
	vec3 col = mix(sand, rock, rocky);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.75, rocky);
	SPECULAR = 0.2;
	// Caustics on up-facing ground, strongest on the shelf.
	vec2 cu = wpos.xz * 0.05;
	float c1 = texture(tex, cu + vec2(TIME * 0.023, TIME * 0.014)).r;
	float c2 = texture(tex, cu * 1.37 + vec2(-TIME * 0.018, TIME * 0.027)).g;
	float c = min(c1, c2);
	float cfade = clamp(1.0 - length(fwidth(cu)) * 1.4, 0.0, 1.0);
	float caus = c * up * up * (1.0 - smoothstep(0.1, 0.8, depth)) * mix(0.35, 1.0, cfade);
	vec3 e = caustic_col * caus * caustic_energy * col;
	// Bioluminescence in the deep: sparse pulsing specks, on floors and walls.
	if (depth > 0.35) {
		vec2 g = mix(vec2(wpos.x + wpos.z, wpos.y * 1.4), wpos.xz, step(0.6, up)) * 0.55;
		vec2 id = floor(g);
		vec2 f = fract(g) - 0.5;
		float h = hash(id);
		float spot = step(0.955, h) * smoothstep(0.3, 0.04, length(f));
		float pulse = 0.55 + 0.45 * sin(TIME * (0.8 + h * 2.0) + h * 61.0);
		vec3 gc = mix(glow_a, glow_b, step(0.985, h));
		e += gc * spot * pulse * glow_energy * smoothstep(0.35, 0.8, depth) * mix(0.15, 1.0, fade);
	}
	EMISSION = e;
}
