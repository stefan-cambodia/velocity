// Energy shield bubble: additive Fresnel rim with a moving hex shimmer.
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded, shadows_disabled;

uniform vec3 color : source_color = vec3(0.35, 0.85, 1.0);
instance uniform float strength = 1.0;

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.5);
	float hex = abs(sin(lpos.x * 6.0 + TIME * 3.0) * sin(lpos.y * 6.0 - TIME * 2.0) * sin(lpos.z * 6.0));
	ALBEDO = color * (fres * 1.6 + hex * 0.12) * strength;
}
