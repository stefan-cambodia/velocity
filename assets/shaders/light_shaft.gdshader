// Sun shafts slanting down through the water (Thalassa Deep). Every shaft is
// two vertices per end on its axis (VERTEX, NORMAL = axis direction, both in
// world space); the vertex shader spreads them sideways to face the camera
// around the axis. UV.x -0.5..0.5 across, UV.y 0 top .. 1 bottom, COLOR.r =
// width factor, COLOR.g = flicker phase. Additive, no depth write, no fog
// (fog would add its colour); shafts fade out close to the camera, so flying
// through one never washes out the screen, and far away.
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled, world_vertex_coords;

uniform vec3 col : source_color = vec3(0.3, 0.6, 0.55);
uniform float width = 16.0;
uniform float energy = 0.3;
uniform float near_fade = 60.0;
uniform float far_fade = 650.0;

varying float fade;

void vertex() {
	vec3 axis = normalize(NORMAL);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 side = normalize(cross(axis, cam - VERTEX));
	VERTEX += side * (UV.x * width * COLOR.r);
	vec3 rel = cam - VERTEX;
	float dist = length(rel);
	// Distance from the camera to the shaft's axis, so the whole shaft fades together.
	float axd = length(rel - axis * dot(rel, axis));
	fade = smoothstep(near_fade * 0.3, near_fade, axd) * (1.0 - smoothstep(far_fade * 0.6, far_fade, dist));
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0);
	across = across * across;
	float along = smoothstep(0.0, 0.2, UV.y) * (1.0 - smoothstep(0.55, 1.0, UV.y));
	float flicker = 0.65 + 0.35 * sin(TIME * 0.45 + COLOR.g * 25.0);
	ALBEDO = col * energy * across * along * flicker * fade;
}
