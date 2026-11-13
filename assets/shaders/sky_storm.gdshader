// Night storm sky for Tempest Shoals: a low, heavy cloud deck, faintly lit from
// above by a hidden moon and from below by the sodium lights of the platforms.
// The cloud fields are baked (offshore_clouds.png: R density, G detail, B rolls),
// so a pixel costs two texture fetches. The shader does not use TIME, so the
// radiance map is rendered once; lightning brightens the visible sky through
// Environment.background_energy_multiplier instead of a uniform here.
shader_type sky;

uniform sampler2D clouds : filter_linear_mipmap, repeat_enable;
uniform vec3 zenith : source_color = vec3(0.045, 0.055, 0.075);
uniform vec3 horizon : source_color = vec3(0.1, 0.12, 0.15);
uniform vec3 cloud_dark : source_color = vec3(0.03, 0.036, 0.05);
uniform vec3 cloud_lit : source_color = vec3(0.17, 0.19, 0.24);
uniform vec3 glow_col : source_color = vec3(0.3, 0.17, 0.08);
uniform vec3 sea_col : source_color = vec3(0.07, 0.085, 0.105);
uniform vec3 moon_dir = vec3(0.35, 0.42, -0.84);
uniform float cloud_scale = 0.16;

void sky() {
	vec3 d = normalize(EYEDIR);
	float y = d.y;
	vec3 col;
	if (y > -0.04) {
		float yy = max(y, 0.0);
		// Project onto a cloud plane: perspective packs the deck toward the horizon.
		vec2 uv = d.xz / (yy + 0.1) * cloud_scale;
		vec3 c1 = texture(clouds, uv).rgb;
		vec3 c2 = texture(clouds, uv * 2.6 + vec2(0.31, 0.57)).rgb;
		float dens = clamp(c1.r * 0.6 + c2.r * 0.25 + c1.b * 0.3 - 0.08, 0.0, 1.0);
		vec3 base = mix(horizon, zenith, smoothstep(0.0, 0.55, yy));
		// Thin patches show the moonlit layer above; dense bellies stay dark.
		float moon = pow(max(dot(d, normalize(moon_dir)), 0.0), 5.0);
		vec3 lit = cloud_lit * (0.55 + 1.1 * moon) * (0.75 + 0.5 * c2.g);
		vec3 cc = mix(lit, cloud_dark, dens);
		col = mix(base, cc, 0.92);
		// Sodium glow of the platforms on the cloud base, low in the sky.
		col += glow_col * (0.3 + 0.7 * dens) * exp(-yy * 9.0) * 0.14;
		// Rain haze toward the horizon (the fog colour).
		col = mix(col, horizon, exp(-yy * 16.0));
	} else {
		col = mix(horizon, sea_col, smoothstep(-0.04, -0.2, y));
	}
	COLOR = col;
}
