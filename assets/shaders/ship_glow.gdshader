// Emissive ship parts (engine cores, flux emitters, nav lights). Brightness and
// colour can be driven per instance (thrust, boost, damage flicker).
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, unshaded;

uniform vec3 color : source_color = vec3(1.0, 0.55, 0.2);
uniform float energy = 3.0;
instance uniform float intensity = 1.0;
instance uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec3 c = color * tint.rgb;
	// Hot white core towards the centre of the emitter (UV.y = 0 at the core).
	float core = clamp(1.0 - UV.y, 0.0, 1.0);
	ALBEDO = mix(c, vec3(1.0), core * 0.5 * intensity) * energy * (0.25 + 0.75 * intensity);
}
