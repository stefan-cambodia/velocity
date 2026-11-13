// Cirrus Heights: opaque cumulus heads, the cloud bank and drifting puffs
// (lumpy low-poly meshes). Lit here from the fixed low sun with wrapped
// diffuse: warm gold on the sunward side, lavender in shadow, darker and
// pinker towards the sea of clouds they rise from, and a bright silver lining
// along the silhouette when seen against the sun. Unshaded and cheap.
// `dissolve` (0..1) screen-door fades the mesh out while the camera is inside
// the cloud bank, so its inner surfaces never show as walls.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, shadows_disabled;

uniform vec3 sun_dir = vec3(0.988, 0.156, 0.0);
uniform vec3 lit_col : source_color = vec3(1.0, 0.8, 0.6);
uniform vec3 shade_col : source_color = vec3(0.5, 0.48, 0.7);
uniform vec3 base_col : source_color = vec3(0.6, 0.48, 0.6);
uniform vec3 rim_col : source_color = vec3(1.0, 0.78, 0.5);
uniform float lit_gain = 1.15;
uniform float base_y = 10.0;      // the cloud sea
uniform float base_fade = 90.0;   // metres above it over which the base darkens
uniform float dissolve = 0.0;

varying vec3 wn;
varying vec3 wp;

void vertex() {
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (dissolve > 0.0) {
		vec2 q = floor(FRAGCOORD.xy);
		float dither = fract(dot(q, vec2(0.7548777, 0.5698403)) + 0.5 * fract(q.y * 0.5));
		if (dither < dissolve) {
			discard;
		}
	}
	vec3 n = normalize(wn);
	vec3 sd = normalize(sun_dir);
	float w = clamp((dot(n, sd) + 0.25) / 1.25, 0.0, 1.0);
	w = w * w * (3.0 - 2.0 * w);
	vec3 col = mix(shade_col, lit_col * lit_gain, w);
	// Tops catch the sky, undersides and sides facing away from it darken.
	col *= 0.72 + 0.28 * clamp(n.y * 0.5 + 0.5, 0.0, 1.0) + 0.1 * n.y;
	col = mix(base_col, col, 0.45 + 0.55 * clamp((wp.y - base_y) / base_fade, 0.0, 1.0));
	col *= COLOR.rgb;
	vec3 v = normalize(CAMERA_POSITION_WORLD - wp);
	float rim = pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 3.0);
	float back = pow(clamp(dot(-v, sd), 0.0, 1.0), 3.0);
	col += rim_col * rim * (0.15 + 1.3 * back);
	ALBEDO = col;
}
