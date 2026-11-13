// Summer afternoon sky for Costa Branca: deep blue zenith, pale hazy horizon,
// a hot sun with a wide glare, and a few fair-weather cumulus from a baked
// texture (assets/textures/coastal_clouds.png) projected onto a cloud deck.
// No TIME, so the radiance map is only rendered once.
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.09, 0.28, 0.66);
uniform vec3 mid : source_color = vec3(0.26, 0.52, 0.86);
uniform vec3 horizon : source_color = vec3(0.7, 0.82, 0.92);
uniform vec3 ground : source_color = vec3(0.32, 0.46, 0.55);
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.99, 0.96);
uniform vec3 cloud_shade : source_color = vec3(0.6, 0.67, 0.78);
uniform sampler2D clouds : filter_linear_mipmap, repeat_enable;
uniform float cloud_scale = 0.16;

void sky() {
	vec3 d = normalize(EYEDIR);
	float y = d.y;
	vec3 sd = normalize(LIGHT0_DIRECTION);
	float sun = max(dot(d, sd), 0.0);
	vec3 col;
	if (y > -0.03) {
		float yy = max(y, 0.0);
		col = mix(horizon, mid, smoothstep(0.0, 0.28, pow(yy, 0.7)));
		col = mix(col, zenith, smoothstep(0.25, 1.0, yy));
		// Sun disc and glare (the glare also warms the haze below it).
		col += LIGHT0_COLOR * (smoothstep(0.99955, 0.99975, sun) * 18.0 + pow(sun, 260.0) * 1.2 + pow(sun, 10.0) * 0.16);
		// Clouds on a deck: compressed towards the horizon, thinned out overhead.
		vec2 uv = d.xz / (yy + 0.09) * cloud_scale + vec2(0.37, 0.11);
		vec2 c = texture(clouds, uv).rg;
		float a = c.r * smoothstep(0.0, 0.07, yy);
		vec3 cc = mix(cloud_lit, cloud_shade, c.g * 0.7 * (1.0 - c.r * 0.4));
		cc += LIGHT0_COLOR * pow(sun, 6.0) * 0.35;
		col = mix(col, cc, a * 0.95);
		// Haze band on the horizon.
		col = mix(col, horizon * 1.04, (1.0 - smoothstep(0.0, 0.06, yy)) * 0.55);
	} else {
		col = ground;
	}
	COLOR = col;
}
