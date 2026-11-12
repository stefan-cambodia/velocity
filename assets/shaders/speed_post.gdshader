// Speed post-process on a full-screen quad: radial blur and chromatic
// aberration that grow towards the edges with speed, plus a vignette. The
// centre of the screen (where the player looks) stays sharp.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, skip_vertex_transform, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount = 0.0;          // 0 .. 1 (speed)
uniform float boost = 0.0;           // 0 .. 1
uniform float aberration = 1.0;      // user scale
uniform float vignette = 0.35;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = vec2(0.5, 0.52);
	vec2 d = uv - c;
	float r = length(d * vec2(1.6, 1.0));
	float edge = smoothstep(0.18, 0.75, r);
	float k = (amount * 0.022 + boost * 0.02) * edge;
	vec3 col = vec3(0.0);
	float wsum = 0.0;
	for (int i = 0; i < 4; i++) {
		float t = float(i) / 3.0;
		float w = 1.0 - t * 0.5;
		vec2 o = d * k * t * 2.0;
		col.r += texture(screen_tex, uv - o * (1.0 + 0.25 * aberration * amount)).r * w;
		col.g += texture(screen_tex, uv - o).g * w;
		col.b += texture(screen_tex, uv - o * (1.0 - 0.25 * aberration * amount)).b * w;
		wsum += w;
	}
	col /= wsum;
	float vig = 1.0 - vignette * smoothstep(0.35, 1.0, r) * (0.6 + 0.4 * amount);
	ALBEDO = col * vig;
}
