// Ship livery. One mesh serves every team: vertex colour is a paint mask
// (R = primary, G = secondary, B = accent, remainder = carbon trim) and
// COLOR.a is baked occlusion. Panel lines are drawn procedurally in object space.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 primary : source_color = vec3(0.9, 0.92, 0.95);
uniform vec3 secondary : source_color = vec3(0.06, 0.22, 0.72);
uniform vec3 accent : source_color = vec3(1.0, 0.42, 0.08);
uniform vec3 trim : source_color = vec3(0.035, 0.038, 0.045);
uniform float paint_metal = 0.45;
uniform float paint_rough = 0.24;
uniform float line_dark = 0.55;

varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
}

float line_at(float x, float period, float offset, float width) {
	float d = abs(fract(x / period + offset) - 0.5) * period;
	float aa = fwidth(x) * 1.2;
	float l = 1.0 - smoothstep(width - aa, width + aa, d);
	// Fade lines that are thinner than a pixel instead of letting them shimmer.
	return l * clamp(width * 2.5 / max(aa, 1e-4), 0.0, 1.0);
}

void fragment() {
	vec3 w = COLOR.rgb;
	float tw = clamp(1.0 - w.r - w.g - w.b, 0.0, 1.0);
	vec3 base = primary * w.r + secondary * w.g + accent * w.b + trim * tw;
	float painted = 1.0 - tw;
	// Panel seams: transverse every 0.7 m, two longitudinal lines.
	float l1 = line_at(obj_pos.z, 0.7, 0.21, 0.006);
	float l2 = line_at(abs(obj_pos.x), 10.0, 0.5 - 0.034, 0.006) ;
	float lines = max(l1, l2 * step(abs(obj_pos.x), 0.9)) * painted;
	ALBEDO = base * (1.0 - lines * line_dark) * COLOR.a;
	METALLIC = mix(0.3, paint_metal, painted);
	ROUGHNESS = mix(0.48, paint_rough, painted) + lines * 0.3;
	SPECULAR = 0.55;
	CLEARCOAT = 0.7 * painted;
	CLEARCOAT_ROUGHNESS = 0.08;
}
