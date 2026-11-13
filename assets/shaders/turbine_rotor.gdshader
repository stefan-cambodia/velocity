// Wind turbine rotors (Tempest Shoals), instanced. The mesh is built around the
// hub with the blades in the XY plane; the vertex shader spins it about Z.
// INSTANCE_CUSTOM.x is the phase (0..1) and .y a speed factor per turbine.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_lambert, specular_schlick_ggx;

uniform vec3 albedo : source_color = vec3(0.72, 0.74, 0.77);
uniform float speed = 1.3;

void vertex() {
	float a = TIME * speed * (0.8 + 0.4 * INSTANCE_CUSTOM.y) + INSTANCE_CUSTOM.x * 6.2831853;
	float c = cos(a);
	float s = sin(a);
	VERTEX.xy = vec2(c * VERTEX.x - s * VERTEX.y, s * VERTEX.x + c * VERTEX.y);
	NORMAL.xy = vec2(c * NORMAL.x - s * NORMAL.y, s * NORMAL.x + c * NORMAL.y);
}

void fragment() {
	ALBEDO = albedo * COLOR.rgb;
	ROUGHNESS = 0.45;
	METALLIC = 0.1;
}
