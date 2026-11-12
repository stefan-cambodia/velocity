// Polar twilight with aurora: navy zenith, teal band, pale gold-pink horizon
// on the sun side, animated aurora curtains (green to violet) and stars.
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.01, 0.025, 0.07);
uniform vec3 mid : source_color = vec3(0.03, 0.12, 0.2);
uniform vec3 horizon : source_color = vec3(0.45, 0.55, 0.65);
uniform vec3 sun_side : source_color = vec3(1.0, 0.62, 0.48);
uniform vec3 ground : source_color = vec3(0.55, 0.62, 0.7);
uniform vec3 sun_dir = vec3(0.3, 0.06, 0.95);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float y = d.y;
	vec3 sd = normalize(sun_dir);
	float sun = max(dot(d, sd), 0.0);
	vec3 col;
	if (y > 0.0) {
		float t = pow(y, 0.5);
		col = mix(horizon, mid, smoothstep(0.0, 0.3, t));
		col = mix(col, zenith, smoothstep(0.3, 1.0, t));
		col += sun_side * (pow(sun, 4.0) * 0.55 + pow(sun, 40.0) * 0.6) * (1.0 - smoothstep(0.0, 0.4, y));
		// Aurora: curtains along the azimuth, rippling slowly.
		float az = atan(d.x, d.z);
		float band = smoothstep(0.12, 0.3, y) * (1.0 - smoothstep(0.45, 0.8, y));
		float curtain = noise(vec2(az * 4.0 + TIME * 0.05, 0.0)) * noise(vec2(az * 11.0 - TIME * 0.08, y * 2.0));
		float rays = 0.6 + 0.4 * noise(vec2(az * 60.0, TIME * 0.3));
		float a = smoothstep(0.25, 0.7, curtain) * band * rays;
		vec3 aur = mix(vec3(0.15, 1.0, 0.55), vec3(0.6, 0.25, 1.0), smoothstep(0.25, 0.6, y));
		col += aur * a * 0.9;
		vec2 sp = floor(d.xz / max(y, 0.05) * 140.0);
		float st = step(0.9985, hash(sp)) * smoothstep(0.25, 0.6, y);
		col += vec3(st) * 0.8;
	} else {
		col = mix(horizon * 0.9, ground, smoothstep(0.0, 0.1, -y));
	}
	COLOR = col;
}
