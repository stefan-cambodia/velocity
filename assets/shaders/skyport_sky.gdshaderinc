// Cirrus Heights: the sunrise sky gradient, shared by the sky shader
// (sky_dawn) and the cloud sea (cloud_sea), which fades into exactly this
// colour at its far edge so the horizon has no seam. A handful of
// smoothsteps and pows: cheap enough to evaluate per pixel on a phone.

uniform vec3 sun_dir = vec3(0.988, 0.156, 0.0);
uniform vec3 zenith_col : source_color = vec3(0.12, 0.22, 0.5);
uniform vec3 upper_col : source_color = vec3(0.42, 0.48, 0.78);
uniform vec3 rose_col : source_color = vec3(0.97, 0.63, 0.66);
uniform vec3 gold_col : source_color = vec3(1.0, 0.72, 0.42);
uniform vec3 haze_col : source_color = vec3(0.92, 0.74, 0.72);
uniform vec3 shadow_band : source_color = vec3(0.52, 0.53, 0.74);

// d: normalised view direction (world). Returns linear HDR colour.
vec3 dawn_sky(vec3 d) {
	vec3 sd = normalize(sun_dir);
	float y = d.y;
	vec2 hz = d.xz / max(length(d.xz), 1e-4);
	float toward = dot(hz, normalize(sd.xz)) * 0.5 + 0.5;   // 1 = sun side
	vec3 horizon = mix(rose_col, gold_col, smoothstep(0.4, 1.0, toward));
	float t = sqrt(clamp(y, 0.0, 1.0));
	vec3 col = mix(horizon, upper_col, smoothstep(0.08, 0.6, t));
	col = mix(col, zenith_col, smoothstep(0.5, 1.0, t));
	// Opposite the sun: the pink belt above a blue-grey shadow band.
	float anti = 1.0 - toward;
	col = mix(col, rose_col, anti * smoothstep(0.0, 0.07, y) * (1.0 - smoothstep(0.1, 0.3, y)) * 0.5);
	col = mix(col, shadow_band, anti * anti * (1.0 - smoothstep(0.0, 0.06, y)) * 0.4);
	// Sun glow, strongest along the horizon.
	float mu = max(dot(d, sd), 0.0);
	col += gold_col * (pow(mu, 4.0) * 0.3 + pow(mu, 32.0) * 0.55) * (1.0 - 0.5 * smoothstep(0.1, 0.6, y));
	// Below the horizon: the haze over the far cloud sea.
	vec3 below = mix(haze_col, gold_col * 1.05, pow(toward, 4.0) * 0.55);
	col = mix(col, below, smoothstep(0.0, -0.025, y));
	return col;
}
