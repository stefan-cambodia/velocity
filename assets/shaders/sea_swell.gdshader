// Open sea in a night storm (Tempest Shoals). The mesh is a polar grid that
// follows the camera; its vertices are displaced by the shared Gerstner swell
// in world space, so the waves stay put while the grid slides. The fragment
// adds the small chop from a baked normal map (two scrolling fetches) and
// foam from the same texture's alpha, spreading over the crests.
// `flash` is driven by the lightning (a uniform update, never a recompile).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx, world_vertex_coords, shadows_disabled;

#include "res://assets/shaders/swell.gdshaderinc"

uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
uniform vec3 deep : source_color = vec3(0.012, 0.024, 0.032);
uniform vec3 body : source_color = vec3(0.035, 0.08, 0.09);
uniform vec3 foam_col : source_color = vec3(0.5, 0.55, 0.58);
uniform vec3 sky_col : source_color = vec3(0.05, 0.06, 0.08);
uniform vec3 flash_col : source_color = vec3(0.75, 0.82, 1.0);
uniform float flash = 0.0;
uniform float chop = 0.55;
uniform float foam_base = 0.06;

varying vec3 wn;
varying vec3 wp;
varying float crest;
varying float vdist;

void vertex() {
	float dist = length(VERTEX.xz - CAMERA_POSITION_WORLD.xz);
	vec3 n;
	float h;
	vec3 disp = swell(VERTEX.xz, TIME, dist, n, h);
	VERTEX += disp;
	NORMAL = n;
	wn = n;
	wp = VERTEX;
	crest = h;
	vdist = dist;
}

void fragment() {
	vec2 w = normalize(SWELL_WIND);
	vec2 uv1 = wp.xz * 0.019 + w * TIME * 0.013;
	vec2 uv2 = wp.xz * 0.043 + vec2(w.y, -w.x) * TIME * 0.019;
	vec4 d1 = texture(detail, uv1);
	vec4 d2 = texture(detail, uv2);
	vec2 nd = (d1.xy + d2.xy) - 1.0;
	float near = 1.0 - smoothstep(120.0, 900.0, vdist);
	vec3 n = normalize(wn + vec3(nd.x, 0.0, -nd.y) * chop * (0.35 + 0.65 * near));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float fres = 0.02 + 0.98 * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	// Foam: streaks everywhere in the storm, spreading over the crests.
	float cov = foam_base + smoothstep(0.55, 0.95, crest) * 0.5;
	float pat = d1.a * 0.65 + d2.a * 0.35;
	float foam = smoothstep(1.0 - cov, 1.0 - cov + 0.12, pat);
	foam = mix(foam, cov * 0.7, smoothstep(250.0, 1400.0, vdist));
	vec3 water = mix(deep, body, smoothstep(0.45, 1.0, crest));
	ALBEDO = mix(water, foam_col, foam);
	ROUGHNESS = mix(0.1, 0.8, foam);
	SPECULAR = 0.5;
	// Faint self-light on the foam: whitecaps stay readable in the dark.
	EMISSION = (sky_col * fres + flash_col * flash * (fres * 0.35 + 0.025)) * (1.0 - foam * 0.6) + foam_col * foam * (0.08 + flash * 0.3);
}
