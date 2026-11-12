// Track barriers. UV = (distance s, height h) in metres. UV2.x = 1 on the face
// that looks at the racing surface, UV2.y = side (-1 left, +1 right).
// COLOR.a encodes the turn ahead: 0.5 = straight, 1 = hard right, 0 = hard left.
// On the outside wall of a corner, scrolling chevrons point the way.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(0.78, 0.8, 0.86);
uniform vec3 glow_color : source_color = vec3(0.25, 0.8, 1.0);
uniform vec3 chevron_color : source_color = vec3(1.0, 0.42, 0.08);
uniform float glow_energy = 2.6;
uniform float chevron_energy = 2.4;
uniform float chevron_speed = 9.0;

varying vec2 face;

void vertex() {
	face = UV2;
}

void fragment() {
	vec4 t = texture(albedo_tex, UV / 4.0);
	float h = UV.y;
	float inner = face.x;
	float side = face.y;
	float aa = max(fwidth(h), 0.002);
	// Energy band along the foot of the inner face.
	float band_e = inner * smoothstep(0.12 - aa, 0.12 + aa, h) * (1.0 - smoothstep(0.32 - aa, 0.32 + aa, h));
	// Upper rail light.
	float rail = inner * smoothstep(1.02 - aa, 1.02 + aa, h) * (1.0 - smoothstep(1.1 - aa, 1.1 + aa, h));
	// Chevrons on the outside of corners.
	float turn = (COLOR.a - 0.5) * 2.0;
	float outer = clamp(-turn * side * 1.6, 0.0, 1.0) * inner;
	float hc = (h - 0.66) / 0.24;
	float in_panel = step(abs(hc), 1.0);
	float cs = UV.x * 0.42 - TIME * chevron_speed * 0.42;
	float chev = step(fract(cs - abs(hc) * 0.35), 0.4) * in_panel;
	vec3 alb = t.rgb * tint * COLOR.rgb;
	alb = mix(alb, vec3(0.03), in_panel * outer * 0.85);
	ALBEDO = alb;
	ROUGHNESS = t.a;
	METALLIC = 0.6;
	NORMAL_MAP = texture(normal_tex, UV / 4.0).rgb;
	EMISSION = glow_color * (band_e * glow_energy + rail * glow_energy * 0.6) + chevron_color * chev * outer * chevron_energy;
}
