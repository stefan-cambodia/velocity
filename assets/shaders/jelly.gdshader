// Bioluminescent jellyfish in the deep of Thalassa Deep, instanced. The bell
// pulses (contracts and relaxes), the tentacles trail and wave, the whole
// animal bobs. Additive glow with a bright rim; instance colour (COLOR) picks
// the hue. No fog (it would add its colour): fades with distance instead.
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled, fog_disabled;

uniform float energy = 1.6;
uniform float far_fade = 420.0;

varying float fade;
varying float part;

void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	float ph = fract(sin(dot(base.xz, vec2(12.9898, 78.233))) * 43758.5453) * 6.2831;
	float pulse = sin(TIME * 1.7 + ph);
	part = step(0.0, VERTEX.y);
	VERTEX.xz *= 1.0 - 0.13 * pulse * part;
	VERTEX.y += 0.08 * pulse * part;
	float hang = -min(VERTEX.y, 0.0);
	VERTEX.xz += vec2(sin(TIME * 1.3 + hang * 1.4 + ph), cos(TIME * 1.1 + hang * 1.2 + ph)) * 0.12 * hang;
	VERTEX.y += sin(TIME * 0.35 + ph) * 0.6;
	float dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	fade = 1.0 - smoothstep(far_fade * 0.5, far_fade, dist);
}

void fragment() {
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	float glow = mix(0.6, 0.25 + 1.4 * rim * rim, part);
	ALBEDO = COLOR.rgb * glow * energy * fade;
}
