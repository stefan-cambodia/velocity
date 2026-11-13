// Fish for the Thalassa Deep schools: silver belly, dark blue back, a yellow
// lateral stripe, and a tail beat that grows toward the tail (phase per fish
// from INSTANCE_CUSTOM.x, set by fish_school.gdshader).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 back_col : source_color = vec3(0.12, 0.22, 0.3);
uniform vec3 belly_col : source_color = vec3(0.85, 0.9, 0.88);
uniform vec3 stripe_col : source_color = vec3(0.95, 0.75, 0.25);

varying float side_y;

void vertex() {
	float ph = INSTANCE_CUSTOM.x * 40.0;
	float tail = smoothstep(0.15, -0.55, VERTEX.z);
	VERTEX.x += sin(TIME * 9.0 + ph + VERTEX.z * 4.0) * 0.13 * tail;
	side_y = VERTEX.y;
}

void fragment() {
	vec3 c = mix(belly_col, back_col, smoothstep(-0.03, 0.06, side_y));
	c = mix(c, stripe_col, smoothstep(0.015, 0.0, abs(side_y - 0.02)) * 0.6);
	ALBEDO = c;
	METALLIC = 0.5;
	ROUGHNESS = 0.3;
	EMISSION = c * 0.08;
}
