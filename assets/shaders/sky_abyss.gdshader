// Thalassa Deep: the water column seen from 60 m down. Blue-black below,
// teal toward the surface, a brighter rippled disc overhead where the sky
// shows through the surface (Snell's window), the sun's glare inside it and a
// fan of light shafts slanting down from it. The ripple and the ray pattern
// come from the baked abyss_caustics texture. No TIME: the radiance cubemap is
// rendered once, not every frame. The environment's fog (tinted by depth in
// Abyssal.DepthTint) is blended over this.
shader_type sky;

uniform vec3 deep_col : source_color = vec3(0.004, 0.018, 0.035);
uniform vec3 mid_col : source_color = vec3(0.02, 0.11, 0.15);
uniform vec3 top_col : source_color = vec3(0.09, 0.36, 0.4);
uniform vec3 window_col : source_color = vec3(0.55, 0.85, 0.8);
uniform vec3 sun_dir = vec3(0.25, 0.92, -0.3);
uniform sampler2D caustic_tex : filter_linear_mipmap, repeat_enable;

void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	vec3 col = mix(deep_col, mid_col, smoothstep(-0.7, 0.1, y));
	col = mix(col, top_col, smoothstep(0.05, 0.9, y));
	// Snell's window: the sky above the surface squeezed into a 48.6 deg cone.
	float cw = 0.6613;
	vec2 puv = d.xz / max(y, 0.08);
	float rip = texture(caustic_tex, puv * 0.11).r;
	float win = smoothstep(cw - 0.05, cw + 0.1, y + (rip - 0.5) * 0.05);
	col += window_col * win * (0.18 + 0.4 * rip);
	vec3 sd = normalize(sun_dir);
	float s = max(dot(d, sd), 0.0);
	col += window_col * (pow(s, 90.0) * 1.6 + pow(s, 12.0) * 0.25);
	// Shafts: streaks fanning out from the sun, fading toward the horizon.
	vec3 t1 = normalize(cross(sd, vec3(0.0, 0.0, 1.0)));
	vec3 t2 = cross(sd, t1);
	float ang = atan(dot(d, t2), dot(d, t1));
	float rays = texture(caustic_tex, vec2(ang / 6.2831853 * 5.0, 0.37)).b;
	rays = smoothstep(0.45, 0.85, rays);
	float fan = smoothstep(-0.25, 0.55, y) * smoothstep(-0.1, 0.8, dot(d, sd));
	col += top_col * rays * fan * 0.45;
	COLOR = col;
}
