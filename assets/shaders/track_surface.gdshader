// Racing surface. UV = (lateral offset d, distance s) in metres; UV2 = (distance
// to the left barrier, distance to the right barrier). COLOR.rgb = baked occlusion,
// COLOR.a = 1 on speed/recharge zones' tint (unused for now).
// Markings are computed analytically so they stay sharp at any distance.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 edge_color : source_color = vec3(0.25, 0.8, 1.0);
uniform vec3 line_color : source_color = vec3(0.86, 0.9, 1.0);
uniform vec3 rhythm_color : source_color = vec3(1.0, 0.55, 0.15);
uniform float tex_size = 8.0;
uniform float edge_energy = 2.4;
uniform float rhythm_energy = 1.8;
uniform float rhythm_spacing = 24.0;
uniform vec3 recharge_color : source_color = vec3(0.25, 1.0, 0.55);
uniform float wetness = 0.0;   // rain: darker deck, glossy puddles reflecting the sky

varying vec2 edge_dist;

void vertex() {
	edge_dist = UV2;
}

float band(float x, float a, float b, float aa) {
	return smoothstep(a - aa, a + aa, x) * (1.0 - smoothstep(b - aa, b + aa, x));
}

void fragment() {
	vec2 uv = UV / tex_size;
	vec4 t = texture(albedo_tex, uv);
	float s = UV.y;
	float de = min(edge_dist.x, edge_dist.y);
	float aa = max(fwidth(de), 0.002);
	// Glowing strip at the foot of each barrier.
	float strip = band(de, 0.35, 0.8, aa);
	// Solid white lane edge line.
	float lane = band(de, 1.45, 1.62, aa);
	// Rhythm bars: short bright blocks every rhythm_spacing metres along both edges.
	float ph = fract(s / rhythm_spacing);
	float aas = max(fwidth(s / rhythm_spacing), 0.0005);
	float bar = band(ph, 0.0, 0.07, aas) * band(de, 0.9, 1.35, aa);
	// Centre dashes.
	float dc = abs(edge_dist.x - edge_dist.y) * 0.5;
	float dash = (1.0 - smoothstep(0.1 - aa, 0.1 + aa, dc)) * band(fract(s / 14.0), 0.0, 0.42, aas * 1.7);
	vec3 alb = t.rgb * tint * COLOR.rgb;
	alb = mix(alb, line_color * 0.75, lane * 0.85 + dash * 0.45);
	alb = mix(alb, vec3(0.02), strip * 0.6);
	float rough = mix(clamp(t.a + 0.25, 0.0, 1.0), 0.5, lane);
	float spec = 0.35;
	if (wetness > 0.0) {
		// Puddle shapes from the same texture at a coarser scale (one extra fetch).
		float puddle = smoothstep(0.45, 0.62, texture(albedo_tex, uv * 0.17 + 0.31).a);
		alb *= mix(1.0, 0.55, wetness);
		rough = mix(rough, mix(0.3, 0.05, puddle), wetness);
		spec = mix(spec, 0.65, wetness);
	}
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = 0.05;
	SPECULAR = spec;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = 0.6;
	// Recharge strip (vertex alpha 0): soft green chevrons flowing along the track.
	float rech = 1.0 - COLOR.a;
	float ca = fwidth(s / 8.0);
	float chev = band(fract(s / 8.0 - abs(UV.x) * 0.05 - TIME * 1.5), 0.02, 0.1, ca) * clamp(1.0 - ca * 12.0, 0.0, 1.0);
	EMISSION = edge_color * strip * edge_energy + rhythm_color * bar * rhythm_energy + line_color * (lane * 0.08 + dash * 0.05)
		+ recharge_color * rech * (0.01 + chev * 0.35);
}
