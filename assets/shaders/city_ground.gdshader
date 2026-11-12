// City floor: dark concrete blocks with glowing street grid and moving traffic dots.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform vec3 base : source_color = vec3(0.045, 0.045, 0.055);
uniform vec3 street : source_color = vec3(1.0, 0.62, 0.3);
uniform vec3 traffic : source_color = vec3(1.0, 0.9, 0.8);
uniform float block = 90.0;
uniform float street_w = 14.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 g = mod(p, block);
	vec2 dist = min(g, block - g);
	float st = 1.0 - smoothstep(street_w * 0.5 - 1.0, street_w * 0.5, min(dist.x, dist.y));
	vec2 w = fwidth(p);
	float fade = clamp(1.0 - length(w) * 0.05, 0.0, 1.0);
	// Traffic: dots moving along the streets.
	float lane_x = step(dist.x, street_w * 0.5) * step(fract((p.y + TIME * 18.0) / 23.0), 0.06);
	float lane_z = step(dist.y, street_w * 0.5) * step(fract((p.x - TIME * 15.0) / 29.0), 0.06);
	float cars = max(lane_x, lane_z) * fade;
	ALBEDO = mix(base, base * 0.6, st);
	ROUGHNESS = 0.8;
	EMISSION = street * st * 0.22 * mix(1.0, 0.6, 1.0 - fade) + traffic * cars * 1.2;
}
