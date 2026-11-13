// Mediterranean sea in sunshine: clear turquoise over the sand in the shallows,
// deepening to ultramarine, glossy ripples that catch the sun, and foam where
// the water meets the shore. Water depth comes from a small texture baked from
// the terrain height field (R = clamp(-h / depth_scale + 0.1)), so no depth
// buffer read is needed. Ripples are a baked normal map sampled twice.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, shadows_disabled;

uniform sampler2D depth_tex : filter_linear, repeat_disable;
uniform sampler2D ripples : filter_linear_mipmap, repeat_enable;   // RGB normal, A foam noise
uniform vec4 hf_rect = vec4(0.0, 0.0, 1.0, 1.0);   // x0, z0, size x, size z of the depth texture
uniform float depth_scale = 30.0;
uniform vec3 sand : source_color = vec3(0.62, 0.86, 0.78);
uniform vec3 shallow : source_color = vec3(0.12, 0.66, 0.68);
uniform vec3 mid : source_color = vec3(0.03, 0.42, 0.58);
uniform vec3 deep : source_color = vec3(0.015, 0.14, 0.34);
uniform vec3 sky_col : source_color = vec3(0.55, 0.72, 0.9);
uniform vec3 foam_col : source_color = vec3(0.96, 0.98, 1.0);
uniform float chop = 0.4;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = (wpos.xz - hf_rect.xy) / hf_rect.zw;
	vec2 inb = step(vec2(0.0), uv) * step(uv, vec2(1.0));
	float inside = inb.x * inb.y;
	float e = texture(depth_tex, clamp(uv, vec2(0.001), vec2(0.999))).r;
	float depth = mix(60.0, (e - 0.1) * depth_scale, inside);
	float t = TIME;
	vec2 p = wpos.xz;
	vec2 uv1 = p * 0.021 + vec2(t * 0.011, t * 0.007);
	vec2 uv2 = p * 0.057 - vec2(t * 0.019, -t * 0.013);
	vec3 n1 = texture(ripples, uv1).xyz * 2.0 - 1.0;
	vec3 n2 = texture(ripples, uv2).xyz * 2.0 - 1.0;
	float fa = texture(ripples, uv2 * 1.7 + n1.xy * 0.05).a;
	// Calmer water in the shallows and far away (keeps the horizon from shimmering).
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float k = chop * mix(0.35, 1.0, smoothstep(0.5, 5.0, depth)) * (1.0 - smoothstep(250.0, 1800.0, dist) * 0.8);
	vec3 n = normalize(vec3((n1.x + n2.x) * k, 1.0, (n1.y + n2.y) * k));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	// Colour by depth: sand showing through, turquoise, then deep blue.
	vec3 water = mix(sand, shallow, smoothstep(0.0, 2.5, depth));
	water = mix(water, mid, smoothstep(2.5, 9.0, depth));
	water = mix(water, deep, smoothstep(9.0, 30.0, depth));
	// Shore foam: a band at the waterline with waves washing in.
	float wash = sin(depth * 3.5 - t * 1.4 + fa * 5.0) * 0.5 + 0.5;
	float band = 1.0 - smoothstep(0.0, 1.1, depth);
	float foam = clamp(band * (0.45 + 0.55 * wash) * smoothstep(0.25, 0.55, fa + band * 0.35), 0.0, 1.0);
	foam = max(foam, (1.0 - smoothstep(-0.3, 0.25, depth)) * 0.9);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	ALBEDO = mix(water, foam_col, foam);
	ROUGHNESS = mix(0.05, 0.7, foam);
	METALLIC = 0.0;
	SPECULAR = 0.55;
	EMISSION = sky_col * fres * 0.45 * (1.0 - foam);
}
