// Photovoltaic blanket: deep blue cells with silver bus lines and a frame
// every panel. Grid contrast fades with its own screen-space density, so far
// wings settle to their average colour instead of shimmering.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 cell_col : source_color = vec3(0.015, 0.03, 0.12);
uniform vec3 line_col : source_color = vec3(0.5, 0.52, 0.58);
uniform vec2 cells = vec2(6.0, 8.0);

void fragment() {
	vec2 g = UV * cells;
	vec2 fw = fwidth(g);
	vec2 f = abs(fract(g) - 0.5);
	vec2 l = smoothstep(vec2(0.45) - fw, vec2(0.45) + fw, f);
	float line = max(l.x, l.y) * (1.0 - smoothstep(0.15, 0.5, max(fw.x, fw.y)));
	vec2 pf = abs(fract(UV) - 0.5);
	vec2 fw2 = fwidth(UV);
	vec2 pl = smoothstep(vec2(0.49) - fw2, vec2(0.49) + fw2, pf);
	float frame = max(pl.x, pl.y);
	float m = max(line * 0.55, frame);
	ALBEDO = mix(cell_col, line_col, m) + vec3(0.0, 0.0, 0.02) * (1.0 - m);
	METALLIC = mix(0.3, 0.9, m);
	ROUGHNESS = mix(0.1, 0.35, m);
	SPECULAR = 0.7;
}
