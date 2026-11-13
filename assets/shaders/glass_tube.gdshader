// Pressure glass of the Thalassa Deep tubes: one thin transparent layer,
// unshaded, faces pointing into the tube (cull_back), so from inside and from
// outside only one wall is ever drawn. Alpha is low face-on and rises at
// grazing angles (Fresnel), so the side walls stay clear while the tube ahead
// reads as a teal tunnel. Faint panel seams (UV = metres around / along), a
// slow sheen and a reflection of the bright surface far above keep the glass
// visible from outside too. No depth write, no shadows.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.3, 0.68, 0.72);
uniform vec3 seam_col : source_color = vec3(0.55, 0.9, 1.0);
uniform vec3 sky_col : source_color = vec3(0.45, 0.8, 0.8);
uniform float base_alpha = 0.05;
uniform float edge_alpha = 0.5;
uniform float panel_around = 4.2;
uniform float panel_along = 8.0;

void fragment() {
	float f = 1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0);
	float fres = f * f * f;
	vec2 p = UV / vec2(panel_around, panel_along);
	vec2 q = abs(fract(p) - 0.5);
	float aa = clamp(1.0 - length(fwidth(p)) * 6.0, 0.0, 1.0);
	float seam = smoothstep(0.475, 0.495, max(q.x, q.y)) * aa;
	float sheen = smoothstep(0.6, 1.0, sin(UV.x * 0.35 + UV.y * 0.02) * 0.5 + 0.5) * 0.25;
	vec3 r = (INV_VIEW_MATRIX * vec4(reflect(-VIEW, NORMAL), 0.0)).xyz;
	float sky = smoothstep(0.25, 0.95, r.y);
	ALBEDO = tint * (0.3 + 0.7 * fres + sheen) + seam_col * seam * 0.45 + sky_col * sky * 0.35;
	ALPHA = clamp(base_alpha + edge_alpha * fres + sheen * 0.05 + seam * 0.25 + sky * 0.07, 0.0, 0.7);
}
