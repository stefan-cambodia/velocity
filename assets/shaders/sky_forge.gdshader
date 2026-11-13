// Night over the volcanic island: a near-black zenith, a warm haze on the
// horizon, and low ash clouds lit orange from below by the lava, strongest
// toward the caldera (glow_dir, from the circuit centre). The cloud field is
// a baked tileable texture (forge_clouds.png) sampled by planar projection,
// two lookups, no per-pixel noise. No TIME: the radiance map renders once.
shader_type sky;

uniform vec3 zenith : source_color = vec3(0.004, 0.005, 0.011);
uniform vec3 horizon : source_color = vec3(0.05, 0.036, 0.04);
uniform vec3 glow_col : source_color = vec3(1.0, 0.46, 0.16);
uniform vec3 ash_col : source_color = vec3(0.012, 0.011, 0.013);
uniform vec3 below : source_color = vec3(0.012, 0.01, 0.012);
uniform vec2 glow_dir = vec2(0.97, -0.25);
uniform float glow_amount = 1.0;
uniform sampler2D clouds : filter_linear_mipmap, repeat_enable;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float y = d.y;
	vec2 hd = normalize(d.xz + vec2(1e-5));
	float toward = dot(hd, normalize(glow_dir)) * 0.5 + 0.5;
	float lean = pow(toward, 4.0);
	vec3 col;
	if (y > -0.03) {
		float yy = max(y, 0.0);
		col = mix(horizon, zenith, smoothstep(0.0, 0.4, pow(yy, 0.6)));
		// Lava light in the haze along the horizon, strongest toward the caldera.
		col += glow_col * exp(-yy * 11.0) * (0.02 + 0.14 * lean) * glow_amount;
		// Stars where the sky is clear, high up.
		vec3 sp = floor(d * 420.0);
		float st = step(0.9982, hash(sp)) * smoothstep(0.2, 0.55, yy);
		// Ash clouds on a layer: planar projection, two scales.
		vec2 cp = d.xz / (yy + 0.07) * 0.06;
		float c1 = texture(clouds, cp).r;
		float c2 = texture(clouds, cp * 2.9 + vec2(0.37, 0.11)).r;
		float dens = c1 * 0.75 + c2 * 0.4;
		float cov = smoothstep(0.38, 0.82, dens) * smoothstep(-0.03, 0.05, y);
		// Lit from below: brighter low on the sky and toward the caldera, and in
		// the thick parts (the glow scatters through them).
		float under = (0.12 + 0.88 * lean) * (1.0 - smoothstep(0.0, 0.55, yy));
		vec3 ccol = ash_col + glow_col * (0.006 + 0.13 * under * glow_amount) * (0.25 + 1.1 * c2 * c2);
		col += vec3(st) * (0.5 + 0.5 * hash(sp + 7.0)) * (1.0 - cov);
		col = mix(col, ccol, cov * 0.92);
	} else {
		col = mix(horizon * 0.6, below, smoothstep(-0.03, -0.15, y));
	}
	COLOR = col;
}
