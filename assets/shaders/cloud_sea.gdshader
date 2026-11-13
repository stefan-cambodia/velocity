// Cirrus Heights: the sea of clouds below the circuit. One large plane that
// follows the camera; the cloud tops come from a baked tileable texture
// (tools/gen_skyport_textures.py: R sunlight incl. long shadows from the low
// sun, G height, B ambient) sampled at three scales and rotations so the
// repeat does not show. Lighting is baked: the shader maps it between a
// lavender shadow and a peach-gold sunlit colour, adds the warm forward glow
// towards the sun and fades into the sky's below-horizon colour with
// distance (its own aerial perspective, so scene fog is off here).
// Unshaded, three fetches, no noise.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, shadows_disabled, fog_disabled;

#include "res://assets/shaders/skyport_sky.gdshaderinc"

uniform sampler2D clouds_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tile = 2400.0;           // metres per repeat (CLOUD_TILE in the generator)
uniform vec3 lit_col : source_color = vec3(1.0, 0.74, 0.52);
uniform vec3 shade_col : source_color = vec3(0.44, 0.43, 0.64);
uniform vec3 fold_col : source_color = vec3(0.28, 0.26, 0.46);
uniform float lit_gain = 1.12;
uniform float haze_near = 300.0;
uniform float haze_far = 8400.0;
uniform vec3 bank_col : source_color = vec3(1.0, 0.9, 0.84);
uniform float bank_fog = 0.0;          // set while the camera is inside the cloud bank

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz / tile;
	vec3 a = texture(clouds_tex, uv).rgb;
	vec2 uv2 = mat2(vec2(0.8, -0.6), vec2(0.6, 0.8)) * uv * 3.3 + vec2(0.31, 0.77);
	vec3 b = texture(clouds_tex, uv2).rgb;
	// Very large scale: thicker and thinner fields of cloud.
	float macro = texture(clouds_tex, mat2(vec2(0.6, 0.8), vec2(-0.8, 0.6)) * uv * 0.23).g;
	float sun = a.r * (0.6 + 0.8 * b.r);
	float h = a.g * 0.7 + b.g * 0.3;
	float amb = a.b * (0.75 + 0.25 * b.b) * (0.75 + 0.35 * macro);
	float lit = smoothstep(0.04, 0.55, sun);
	vec3 col = mix(fold_col, shade_col, clamp(amb * 1.25, 0.0, 1.0));
	col = mix(col, lit_col * lit_gain, lit * (0.55 + 0.45 * h));
	col *= 0.85 + 0.3 * macro;
	// Towards the low sun the cloud tops glow through (forward scattering).
	vec3 v = normalize(wpos - CAMERA_POSITION_WORLD);
	vec3 sd = normalize(sun_dir);
	float fs = pow(max(dot(v, sd), 0.0), 5.0);
	col += gold_col * fs * (0.2 + 0.6 * h) * 0.8;
	// Aerial perspective: fade into the sky's below-horizon colour in this direction.
	float dist = length(wpos.xz - CAMERA_POSITION_WORLD.xz);
	float haze = pow(smoothstep(haze_near, haze_far, dist), 0.6);
	col = mix(col, dawn_sky(v), haze);
	col = mix(col, bank_col, bank_fog * 0.85);
	ALBEDO = col;
}
