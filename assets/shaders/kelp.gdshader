// Giant kelp for Thalassa Deep, instanced in MultiMesh cells. The strand
// sways in a slow current: the bend grows with the square of the height above
// the instance's root, the phase rolls across the forest with world position,
// and a faster flutter shakes the blades. Instance colour (COLOR) tints.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx, world_vertex_coords;

uniform vec3 col_a : source_color = vec3(0.3, 0.27, 0.07);
uniform vec3 col_b : source_color = vec3(0.62, 0.45, 0.12);
uniform vec2 current = vec2(0.8, 0.35);
uniform float sway = 1.0;

varying float hb;

void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	hb = max(VERTEX.y - base.y, 0.0);
	float ph = dot(base.xz, vec2(0.035, 0.021));
	float t = TIME * 0.55 + ph;
	float bend = hb * hb * 0.0032 * sway;
	vec2 d = current * (sin(t) * 0.75 + 0.4) * bend;
	d += vec2(sin(t * 2.7 + hb * 0.35), cos(t * 2.1 + hb * 0.3)) * 0.035 * hb;
	VERTEX.xz += d;
}

void fragment() {
	vec3 c = mix(col_a, col_b, clamp(hb / 22.0, 0.0, 1.0)) * COLOR.rgb;
	ALBEDO = c;
	ROUGHNESS = 0.55;
	SPECULAR = 0.35;
	// A little light through the fronds.
	EMISSION = c * 0.12;
}
