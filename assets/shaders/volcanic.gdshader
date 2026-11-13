// Volcanic island terrain at night: black basalt and cooled lava, ash on the
// gentle slopes, rust-red scoria patches, columnar basalt (vertical joints) on
// steep faces and black sand at the waterline. Vertex colour R carries heat
// (0..1, from the lava distance fields): hot ground shows glowing cracks and a
// dull red bloom. All noise comes from the baked forge_noise texture.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 basalt : source_color = vec3(0.085, 0.08, 0.085);
uniform vec3 ash : source_color = vec3(0.16, 0.15, 0.145);
uniform vec3 scoria : source_color = vec3(0.26, 0.11, 0.07);
uniform vec3 sand : source_color = vec3(0.03, 0.03, 0.034);
uniform vec3 lava_col : source_color = vec3(1.0, 0.3, 0.05);
uniform float glow = 5.0;
uniform float sea_y = 0.0;

varying vec3 wpos;
varying vec3 wn;
varying float heat;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	heat = COLOR.r;
}

void fragment() {
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);
	vec4 n1 = texture(noise_tex, wpos.xz * 0.0031);
	vec4 n2 = texture(noise_tex, wpos.xz * 0.027);
	// Gentle ground: ash over cooled lava on the flanks, rust patches of
	// scoria; the low ground by the sea is a field of black, glossy lava.
	float field = 1.0 - smoothstep(16.0, 34.0, wpos.y + (n1.r - 0.5) * 20.0);
	float ashy = smoothstep(0.42, 0.62, n1.b + (0.18 - slope) * 1.2) * (1.0 - field * 0.85);
	vec3 col = mix(basalt * (0.8 + 0.5 * n2.r), ash * (0.8 + 0.4 * n2.b), ashy);
	col = mix(col, scoria * (0.7 + 0.5 * n2.r), smoothstep(0.66, 0.78, n1.r) * (1.0 - smoothstep(0.2, 0.4, slope)) * (1.0 - field));
	// Ropey lava ridges on the flats (cell edges of the noise texture).
	col *= mix(1.0, 0.55 + 0.45 * smoothstep(0.0, 0.3, n2.g), 1.0 - ashy);
	col *= mix(1.0, 0.6, field);
	// Steep faces: columnar basalt with vertical joints and horizontal breaks.
	float rocky = smoothstep(0.16, 0.34, slope + (n1.r - 0.5) * 0.12);
	vec2 hz = normalize(wn.xz + vec2(1e-4));
	float along = dot(wpos.xz, vec2(-hz.y, hz.x));
	float cw = 2.4;
	float cid = floor(along / cw);
	float cj = abs(fract(along / cw) - 0.5) * 2.0;
	float shade = texture(noise_tex, vec2(cid * 0.071, 0.13)).a;
	float hb = abs(fract(wpos.y / 6.5 + shade * 0.7) - 0.5) * 2.0;
	float joint = smoothstep(0.82, 0.97, cj) + (1.0 - smoothstep(0.0, 0.06, 1.0 - hb)) * 0.6;
	vec2 w = fwidth(wpos.xz);
	float fade = clamp(1.0 - length(w) * 0.35, 0.0, 1.0);
	vec3 cols = basalt * (0.75 + 0.6 * shade) * (1.0 - clamp(joint, 0.0, 1.0) * 0.6 * fade);
	col = mix(col, cols, rocky);
	// Black sand at the waterline.
	float beach = 1.0 - smoothstep(sea_y + 0.6, sea_y + 3.0, wpos.y + n2.r * 1.5);
	col = mix(col, sand, beach);
	// Heat: glowing cracks (two scales, only part of the cell net, so they
	// wander) and a dull bloom on the hottest ground.
	float h = heat;
	vec4 k1 = texture(noise_tex, wpos.xz * 0.013 + n1.rb * 0.08);
	vec4 k2 = texture(noise_tex, wpos.xz * 0.047 + vec2(0.3, 0.7) + n2.rb * 0.05);
	float c1 = (1.0 - smoothstep(0.01, 0.06, k1.g)) * smoothstep(0.35, 0.6, k1.a + n2.r * 0.4 - 0.2);
	float c2 = (1.0 - smoothstep(0.015, 0.07, k2.g)) * smoothstep(0.45, 0.75, k2.a + n1.r * 0.4 - 0.2);
	float hot = h * h;
	float crack = c1 * smoothstep(0.2, 0.7, h) + c2 * smoothstep(0.5, 0.95, h) * 0.7;
	vec3 em = lava_col * glow * (crack * (0.2 + 0.8 * hot) + hot * 0.02);
	EMISSION = em * mix(0.6, 1.0, fade);
	ALBEDO = col * (1.0 - 0.5 * clamp(crack, 0.0, 1.0));
	// Relief: bump the normal from the noise field (two offset lookups), more
	// on steep rock, faded out with distance before it aliases.
	vec2 bp = wpos.xz * 0.045;
	float h0 = texture(noise_tex, bp).r;
	float hx = texture(noise_tex, bp + vec2(0.012, 0.0)).r;
	float hzb = texture(noise_tex, bp + vec2(0.0, 0.012)).r;
	float bump = mix(2.2, 4.5, rocky) * fade;
	vec3 nb = normalize(wn + vec3(h0 - hx, 0.0, h0 - hzb) * bump);
	NORMAL = normalize((VIEW_MATRIX * vec4(nb, 0.0)).xyz);
	ROUGHNESS = mix(mix(mix(0.92, 0.78, field * (1.0 - ashy)), 0.7, rocky), 0.3, beach);
	SPECULAR = mix(0.25, 0.55, beach);
}
