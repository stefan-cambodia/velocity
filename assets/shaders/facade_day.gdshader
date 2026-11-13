// Whitewashed houses in daylight. UV = facade coordinates in metres (u along
// the wall, v above the house's base). COLOR.rgb = wall tint, COLOR.a = a
// per-house seed (0 = a plain surface: roofs, parapets, chimneys). Windows,
// shutters, doors and the painted plinth are drawn per floor and bay from a
// hash of the cell, so they cost no geometry; they fade to their average
// colour with distance before they could shimmer.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float floor_h = 3.2;

varying vec3 wpos;
varying vec3 wn;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 wall = COLOR.rgb * COLOR.rgb;   // tints are given in sRGB
	float seed = COLOR.a;
	vec3 nz = texture(noise_tex, wpos.xz * 0.013 + wpos.y * 0.021).rgb;
	// Lime-wash: faint blotches and a little grime near the ground.
	wall *= 0.93 + 0.1 * nz.g;
	vec2 m = UV;
	float plain = step(seed, 0.001);
	float vertical = 1.0 - step(0.5, abs(wn.y));
	float on = (1.0 - plain) * vertical;
	// Palette from the seed: shutter/door colour and plinth colour.
	float s1 = fract(seed * 7.13);
	float s2 = fract(seed * 13.7);
	// Linear colours: deep Mediterranean blue, sea green, olive green, brown.
	vec3 shutter = s1 < 0.45 ? vec3(0.01, 0.06, 0.32) : (s1 < 0.7 ? vec3(0.005, 0.12, 0.16) : (s1 < 0.85 ? vec3(0.02, 0.1, 0.025) : vec3(0.15, 0.04, 0.012)));
	vec3 plinth_c = s2 < 0.4 ? vec3(0.012, 0.05, 0.3) : (s2 < 0.7 ? vec3(0.62, 0.3, 0.03) : vec3(0.16, 0.16, 0.16));
	float bay = 2.7 + 0.8 * fract(seed * 3.31);
	vec2 cell = floor(vec2(m.x / bay, m.y / floor_h));
	vec2 f = vec2(fract(m.x / bay), fract(m.y / floor_h));
	float h = hash(cell + seed * 91.7);
	// Fade the openings with distance (pixel footprint in metres).
	float px = length(fwidth(m));
	float detail = 1.0 - smoothstep(0.25, 0.7, px);
	float ground_floor = 1.0 - step(1.0, cell.y);
	float has_win = step(0.3, h) * on;
	float win = step(0.33, f.x) * step(f.x, 0.67) * step(0.34, f.y) * step(f.y, 0.78) * has_win * (1.0 - ground_floor * step(0.78, h));
	float shut = (step(0.17, f.x) * step(f.x, 0.31) + step(0.69, f.x) * step(f.x, 0.83)) * step(0.34, f.y) * step(f.y, 0.78) * has_win * step(0.4, s1 + h * 0.4);
	float door = ground_floor * step(0.78, h) * step(0.32, f.x) * step(f.x, 0.68) * step(f.y, 0.74) * on;
	float lintel = (step(0.3, f.x) * step(f.x, 0.7) * step(0.78, f.y) * step(f.y, 0.83)) * has_win * 0.5;
	float plinth = step(m.y, 0.75) * on;
	vec3 glass = vec3(0.012, 0.014, 0.018) + vec3(0.02, 0.03, 0.05) * smoothstep(0.5, 0.9, f.y);
	vec3 col = wall;
	col = mix(col, plinth_c, plinth);
	col = mix(col, wall * 0.82, lintel * detail);
	col = mix(col, shutter, shut * detail);
	col = mix(col, glass, win * detail);
	col = mix(col, shutter * 0.8, door * detail);
	// Far away: average the openings into the wall.
	float avg = on * (1.0 - detail) * 0.12;
	col = mix(col, mix(wall, vec3(0.2, 0.22, 0.28), 0.5), avg);
	ALBEDO = col;
	ROUGHNESS = mix(0.85, 0.25, win * detail);
	SPECULAR = mix(0.35, 0.6, win * detail);
}
