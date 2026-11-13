// Cirrus Heights sky: sunrise gradient from deep blue overhead to rose and
// gold at the horizon (skyport_sky.gdshaderinc), the low sun with its disc,
// and pink-lit cirrus from one baked tileable texture (gen_skyport_textures.py)
// projected on a high plane. No TIME and no per-pixel noise: the radiance
// cubemap is rendered once and the background costs a couple of fetches.
shader_type sky;

#include "res://assets/shaders/skyport_sky.gdshaderinc"

uniform sampler2D cirrus_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 cirrus_lit : source_color = vec3(1.0, 0.78, 0.68);
uniform vec3 cirrus_shade : source_color = vec3(0.78, 0.66, 0.82);

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 sd = normalize(sun_dir);
	vec3 col = dawn_sky(d);
	float mu = dot(d, sd);
	if (d.y > 0.0) {
		vec2 uv = d.xz / (d.y + 0.08) * 0.11 + vec2(0.37, 0.12);
		float c = texture(cirrus_tex, uv).r;
		c *= smoothstep(0.0, 0.1, d.y) * (1.0 - smoothstep(0.55, 0.95, d.y));
		vec3 cc = mix(cirrus_shade, cirrus_lit, smoothstep(-0.2, 0.9, mu));
		cc += gold_col * pow(max(mu, 0.0), 12.0) * 0.8;
		col = mix(col, cc, c * 0.75);
	}
	// The sun: a soft-edged disc about one degree across.
	col += vec3(1.0, 0.86, 0.62) * smoothstep(0.99975, 0.99992, mu) * 18.0;
	COLOR = col;
}
