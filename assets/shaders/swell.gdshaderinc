// Storm swell for Tempest Shoals, shared by the sea surface and the foam around
// the legs so both ride the same waves. Four Gerstner waves around the wind
// direction; shorter waves fade out with distance from the camera, where the
// camera-following sea mesh gets too coarse to carry them.
// Peak crest height above mean sea level: SWELL_AMP (sum of the amplitudes).

const vec2 SWELL_WIND = vec2(0.6, 0.8);
const float SWELL_AMP = 3.7;

vec2 swell_rot(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

void swell_wave(vec2 p, float t, vec2 dir, float lambda, float amp, float q, float dist,
		inout vec3 disp, inout vec3 tx, inout vec3 tz) {
	amp *= 1.0 - smoothstep(lambda * 3.0, lambda * 5.5, dist);
	float k = 6.2831853 / lambda;
	float c = sqrt(9.81 / k);
	float f = k * (dot(dir, p) - c * t);
	float s = sin(f);
	float co = cos(f);
	float qa = q * amp;
	disp.x += dir.x * qa * co;
	disp.z += dir.y * qa * co;
	disp.y += amp * s;
	float wa = k * amp;
	float qwa = q * wa * s;
	tx += vec3(-dir.x * dir.x * qwa, dir.x * wa * co, -dir.x * dir.y * qwa);
	tz += vec3(-dir.x * dir.y * qwa, dir.y * wa * co, -dir.y * dir.y * qwa);
}

// Displacement of the sea surface point that rests at (p.x, 0, p.y). `dist` is
// the horizontal distance from the camera. Returns the world normal in `nrm`
// and the crest height 0..1 (trough..crest) in `h01`.
vec3 swell(vec2 p, float t, float dist, out vec3 nrm, out float h01) {
	vec3 disp = vec3(0.0);
	vec3 tx = vec3(1.0, 0.0, 0.0);
	vec3 tz = vec3(0.0, 0.0, 1.0);
	vec2 w = normalize(SWELL_WIND);
	swell_wave(p, t, w, 160.0, 1.8, 1.6, dist, disp, tx, tz);
	swell_wave(p, t * 1.03, swell_rot(w, 0.42), 101.0, 1.0, 1.8, dist, disp, tx, tz);
	swell_wave(p, t * 0.97, swell_rot(w, -0.57), 63.0, 0.6, 2.0, dist, disp, tx, tz);
	swell_wave(p, t, swell_rot(w, 0.9), 37.0, 0.3, 2.0, dist, disp, tx, tz);
	nrm = normalize(cross(tz, tx));
	h01 = clamp(disp.y / SWELL_AMP * 0.5 + 0.5, 0.0, 1.0);
	return disp;
}
