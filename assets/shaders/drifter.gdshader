// The Drifter, the great filter-feeder of Thalassa Deep's trench (an original
// creature): a long flattened body with wide swept wings and a tail fluke.
// Local +Z is forward. The body beats up and down in a wave that grows toward
// the tail, the wings rise and fall slowly (COLOR.g = wing weight, 0 at the
// root, 1 at the tip), and rows of photophores (COLOR.r = 1) pulse.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 back_col : source_color = vec3(0.1, 0.16, 0.22);
uniform vec3 belly_col : source_color = vec3(0.55, 0.62, 0.66);
uniform vec3 glow_col : source_color = vec3(0.2, 0.95, 1.0);
uniform float phase = 0.0;

varying float glow;
varying float ny;
varying float along;

void vertex() {
	float t = TIME * 0.9 + phase;
	float tail = smoothstep(8.0, -40.0, VERTEX.z);
	VERTEX.y += sin(t - VERTEX.z * 0.06) * 2.4 * tail * tail;
	float wing = COLOR.g;
	VERTEX.y += (sin(t * 0.6 + 1.3) * 6.5 - 1.0) * wing * wing;
	glow = COLOR.r;
	ny = NORMAL.y;
	along = VERTEX.z;
}

void fragment() {
	vec3 c = mix(belly_col, back_col, smoothstep(-0.35, 0.35, ny));
	ALBEDO = c;
	ROUGHNESS = 0.45;
	SPECULAR = 0.4;
	float pulse = 0.55 + 0.45 * sin(TIME * 1.6 - along * 0.15 + phase);
	EMISSION = glow_col * glow * pulse * 3.0 + c * 0.05;
}
