// Proving-ground floor: dark plate with a faint survey grid that fades with distance.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 base : source_color = vec3(0.035, 0.04, 0.05);
uniform vec3 line_color : source_color = vec3(0.15, 0.5, 0.7);
uniform float spacing = 50.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 g = wpos.xz / spacing;
	vec2 w = fwidth(g);
	vec2 l = 1.0 - smoothstep(vec2(0.0), w * 1.5, abs(fract(g - 0.5) - 0.5));
	float line = max(l.x, l.y);
	float fade = clamp(1.0 - length(w) * 6.0, 0.0, 1.0);
	ALBEDO = base;
	ROUGHNESS = 0.55;
	METALLIC = 0.3;
	EMISSION = line_color * line * fade * 0.6;
}
