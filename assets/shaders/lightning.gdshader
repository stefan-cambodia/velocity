// Lightning (Tempest Shoals): one mesh holds the bolt ribbons (COLOR.a = 1,
// UV.x across the ribbon) and a soft glow card in the cloud base (COLOR.a = 0,
// radial from the UV centre). Additive and fog-free; `intensity` is driven by
// the storm controller, so a strike is a uniform update, never a recompile or
// a new node. At rest it adds black.
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, fog_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.78, 0.84, 1.0);
uniform float intensity = 0.0;
uniform float bolt = 0.0;   // 1 while the channel is visible, 0 for the afterglow

void fragment() {
	float x = abs(UV.x - 0.5) * 2.0;
	float core = 1.0 - smoothstep(0.0, 1.0, x);
	float ribbon = (core * core * 4.0 + pow(core, 12.0) * 10.0) * COLOR.r * bolt;
	float r = length(UV - 0.5) * 2.0;
	float glow = 1.0 - smoothstep(0.0, 1.0, r);
	glow = glow * glow * glow * 0.14;
	ALBEDO = color * intensity * mix(glow, ribbon, COLOR.a);
}
