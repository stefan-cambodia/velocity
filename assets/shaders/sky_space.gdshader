// Low orbit: layered stars, a dusty galactic band, the sun with glare, a moon,
// and the planet below, found by a ray cast against a unit sphere, so it sits
// at infinity under the whole circuit and never clips. Its surface fields
// (elevation, dryness, clouds, city lights) come from one baked texture of the
// visible cap (tools/gen_textures.py gen_planet), not per-pixel noise, which
// measured as the A56's frame dips in the Hub Spiral. Lighting is computed
// here: oceans with sun glint, a dusk band, cities on the night side and a
// scattering halo along the limb. No TIME: the radiance cubemap is rendered
// once, not every frame.
shader_type sky;

uniform vec3 sun_dir = vec3(0.55, 0.35, -0.75);
uniform vec3 band_col : source_color = vec3(0.35, 0.3, 0.45);
uniform vec3 planet_down = vec3(0.22, -1.0, 0.16);
uniform float altitude = 0.032;  // orbit height in planet radii
uniform vec3 moon_dir = vec3(-0.6, 0.28, -0.55);
uniform float moon_size = 0.04;  // angular radius in radians

uniform vec3 ocean_deep : source_color = vec3(0.008, 0.035, 0.11);
uniform vec3 ocean_shelf : source_color = vec3(0.03, 0.14, 0.24);
uniform vec3 land_col : source_color = vec3(0.13, 0.2, 0.07);
uniform vec3 desert_col : source_color = vec3(0.48, 0.36, 0.2);
uniform vec3 city_col : source_color = vec3(1.0, 0.72, 0.38);
uniform vec3 atmo_col : source_color = vec3(0.32, 0.58, 1.0);
uniform sampler2D cap_tex : filter_linear_mipmap, repeat_disable;
const float CAP_SIN = 0.27564;   // sin(16 deg): half-width of the baked cap

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

vec3 space(vec3 d, vec3 sd) {
	vec3 col = vec3(0.004, 0.005, 0.012);
	vec3 axis = normalize(vec3(0.3, 0.85, 0.42));
	float b = 1.0 - abs(dot(d, axis));
	float dust = noise(d * 9.0) * 0.6 + noise(d * 23.0) * 0.4;
	col += band_col * pow(b, 8.0) * (0.25 + 0.75 * dust) * 0.5;
	for (int k = 0; k < 3; k++) {
		float sc = 220.0 + float(k) * 260.0;
		vec3 c = floor(d * sc);
		float h = hash(c + float(k) * 13.0);
		float thr = 0.9965 - float(k) * 0.0012 - pow(b, 6.0) * 0.004;
		float st = step(thr, h);
		vec3 tint = mix(vec3(0.7, 0.8, 1.0), vec3(1.0, 0.85, 0.7), hash(c + 5.0));
		col += tint * st * (0.5 + 0.5 * hash(c + 9.0)) * (1.2 - float(k) * 0.3);
	}
	// Moon: a lit sphere with maria.
	vec3 md = normalize(moon_dir);
	float mc = dot(d, md);
	float sr = sin(moon_size);
	vec3 q = (d - md * mc) / sr;
	float qq = dot(q, q);
	if (mc > 0.0 && qq < 1.0) {
		vec3 mn = q - md * sqrt(1.0 - qq);
		float lit = clamp(dot(mn, sd) * 1.2, 0.0, 1.0);
		float maria = smoothstep(0.45, 0.6, noise(mn * 4.0 + 2.0)) * 0.35 + noise(mn * 14.0) * 0.15;
		vec3 mcol = vec3(0.62, 0.61, 0.6) * (1.0 - maria) * lit + vec3(0.004, 0.006, 0.012);
		col = mix(col, mcol, smoothstep(1.0, 0.94, qq));
	}
	// The sun.
	float sdot = max(dot(d, sd), 0.0);
	col += vec3(1.0, 0.97, 0.92) * (pow(sdot, 2000.0) * 40.0 + pow(sdot, 120.0) * 0.6 + pow(sdot, 12.0) * 0.06);
	return col;
}

vec3 surface(vec3 n, vec3 d, vec3 sd, float mu, vec3 pd) {
	// Tangent plane at the nadir, the same mapping the generator used.
	vec3 e1 = normalize(cross(pd, vec3(0.0, 0.0, 1.0)));
	vec3 e2 = cross(pd, e1);
	vec2 uv = vec2(dot(n, e1), dot(n, e2)) / CAP_SIN * 0.5 + 0.5;
	vec4 f = texture(cap_tex, uv);
	float land = smoothstep(0.47, 0.53, f.r);
	float shelf = smoothstep(0.25, 0.5, f.r) * (1.0 - land);
	vec3 ground = mix(land_col, desert_col, f.g);
	ground = mix(ground, vec3(0.75, 0.77, 0.8), smoothstep(0.88, 0.96, f.r));
	vec3 surf = mix(mix(ocean_deep, ocean_shelf, shelf), ground, land);
	float cl = f.b;
	float ndl = dot(n, sd);
	float day = smoothstep(-0.08, 0.25, ndl);
	float dusk = smoothstep(-0.1, 0.05, ndl) * (1.0 - smoothstep(0.05, 0.3, ndl));
	vec3 sunlit = mix(vec3(1.0), vec3(1.0, 0.55, 0.3), dusk);
	vec3 col = mix(surf, vec3(0.92), cl * 0.9) * sunlit * (0.15 + 1.1 * clamp(ndl, 0.0, 1.0)) * day;
	// Sun glint on open water.
	vec3 r = reflect(d, n);
	col += vec3(1.0, 0.88, 0.7) * pow(max(dot(r, sd), 0.0), 90.0) * (1.0 - land) * (1.0 - cl) * day * 1.4;
	// Cities on the night side.
	col += city_col * f.a * (1.0 - cl * 0.8) * (1.0 - smoothstep(-0.1, 0.06, ndl)) * 1.5;
	// Aerial perspective toward the limb.
	float haze = pow(1.0 - mu, 5.0);
	col = mix(col, atmo_col * (0.08 + 0.9 * day) * sunlit, haze * 0.85);
	return col;
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 sd = normalize(sun_dir);
	vec3 pd = normalize(planet_down);
	vec3 pc = pd * (1.0 + altitude);
	float b = dot(d, pc);
	float closest = sqrt(max(dot(pc, pc) - b * b, 0.0));
	vec3 col = space(d, sd);
	if (b > 0.0) {
		vec3 limb_n = normalize(d * b - pc);
		float ldl = dot(limb_n, sd);
		float lday = smoothstep(-0.2, 0.2, ldl);
		vec3 rim = mix(atmo_col, vec3(1.0, 0.5, 0.25), smoothstep(-0.2, 0.0, ldl) * (1.0 - smoothstep(0.0, 0.25, ldl)));
		if (closest < 1.0) {
			float t = b - sqrt(1.0 - closest * closest);
			vec3 n = d * t - pc;
			float mu = clamp(dot(n, -d), 0.0, 1.0);
			vec3 s = surface(n, d, sd, mu, pd);
			float edge = smoothstep(1.0, 0.9985, closest);
			col = mix(col, s, edge);
		}
		// Scattering halo hugging the limb.
		float hgt = closest - 1.0;
		float halo = hgt > 0.0 ? exp(-hgt / 0.0045) : exp(hgt / 0.0012);
		col += rim * halo * (0.04 + 0.9 * lday);
	}
	COLOR = col;
}
