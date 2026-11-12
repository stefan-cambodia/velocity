// Late-dusk sky for Helix Bay: deep zenith, magenta/orange horizon band,
// sun glow below the horizon, stars, thin cloud streaks and city light haze.
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.015, 0.03, 0.09);
uniform vec3 mid : source_color = vec3(0.13, 0.08, 0.26);
uniform vec3 horizon : source_color = vec3(0.95, 0.38, 0.22);
uniform vec3 haze : source_color = vec3(0.55, 0.3, 0.45);
uniform vec3 sun_glow : source_color = vec3(1.0, 0.55, 0.25);
uniform vec3 ground : source_color = vec3(0.02, 0.02, 0.035);
uniform vec3 sun_dir = vec3(-0.62, 0.05, 0.78);
uniform float star_amount = 1.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(vec3(i, 1.0));
	float b = hash(vec3(i + vec2(1.0, 0.0), 1.0));
	float c = hash(vec3(i + vec2(0.0, 1.0), 1.0));
	float d = hash(vec3(i + vec2(1.0, 1.0), 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float y = d.y;
	vec3 sd = normalize(sun_dir);
	float sun = max(dot(d, sd), 0.0);
	vec3 col;
	if (y > 0.0) {
		float t = pow(y, 0.45);
		col = mix(horizon, mid, smoothstep(0.0, 0.35, t));
		col = mix(col, zenith, smoothstep(0.3, 1.0, t));
		// Warm glow around the (set) sun, wider near the horizon.
		col += sun_glow * (pow(sun, 6.0) * 0.6 + pow(sun, 60.0) * 0.8) * (1.0 - smoothstep(0.0, 0.5, y));
		// City light haze on the horizon all around.
		col += haze * exp(-y * 18.0) * 0.35;
		// Thin cloud streaks.
		vec2 cp = d.xz / max(y + 0.08, 0.05) * 1.6;
		float cl = noise(cp * vec2(0.6, 3.0) + vec2(TIME * 0.002, 0.0)) * noise(cp * 1.7);
		cl = smoothstep(0.35, 0.75, cl) * smoothstep(0.02, 0.12, y) * (1.0 - smoothstep(0.35, 0.7, y));
		vec3 cloud_col = mix(vec3(0.1, 0.06, 0.15), horizon * 0.8, pow(sun, 3.0) * 0.8 + 0.2);
		col = mix(col, cloud_col, cl * 0.55);
		// Stars above the glow.
		vec3 sp = floor(d * 380.0);
		float st = step(0.9975, hash(sp)) * smoothstep(0.2, 0.6, y) * star_amount;
		col += vec3(st) * (0.6 + 0.4 * hash(sp + 7.0));
	} else {
		col = mix(haze * 0.5, ground, smoothstep(0.0, 0.08, -y));
	}
	COLOR = col;
}
