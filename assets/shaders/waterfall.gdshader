// Falling water: translucent sheets with streaks that race downward, thinning
// at the edges and churning to foam at the foot. UV.x runs 0..1 across the
// sheet, UV.y is metres down / 10, so streaks keep their size on any fall.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, shadows_disabled;

uniform vec3 water_col : source_color = vec3(0.8, 0.86, 0.84);
uniform float speed = 1.8;
uniform float opacity = 0.85;
uniform float foam_from = 0.85;   // fraction of the length where foam starts (COLOR.r carries 0..1 along)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	float t = TIME * speed;
	float flow = vnoise(vec2(UV.x * 16.0, UV.y * 1.1 - t)) * 0.6 + vnoise(vec2(UV.x * 41.0, UV.y * 2.6 - t * 1.6)) * 0.4;
	float edge = smoothstep(0.0, 0.18, UV.x) * smoothstep(1.0, 0.82, UV.x);
	float along = COLOR.r;
	float foam = smoothstep(foam_from, 1.0, along);
	float a = opacity * edge * (0.45 + 0.55 * flow) * mix(0.6, 1.0, smoothstep(0.0, 0.05, along));
	a = mix(a, max(a, 0.9 * edge), foam);
	ALBEDO = water_col * (0.65 + 0.5 * flow) + vec3(0.15) * foam;
	ALPHA = clamp(a, 0.0, 1.0);
	EMISSION = water_col * (0.08 + 0.12 * flow + 0.2 * foam);
	ROUGHNESS = 0.25;
	SPECULAR = 0.6;
}
