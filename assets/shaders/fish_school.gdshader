// Fish school motion for Thalassa Deep (GPUParticles3D process shader). Each
// particle is one fish, placed by formula every frame: the school swims round
// a loop of `radius` metres about the emitter, each fish offset within the
// shoal and trailing a little along the path, bobbing slowly. The basis faces
// the fish along its path (+Z = head). CUSTOM.x carries a per-fish phase for
// the tail beat in fish.gdshader.
shader_type particles;
render_mode disable_velocity;

uniform float radius = 18.0;
uniform float speed = 0.3;      // rad/s, negative swims the other way
uniform float spread = 6.0;     // shoal size
uniform float bob = 2.0;
uniform float size = 1.0;

float h1(float n) {
	return fract(sin(n * 12.9898 + 4.1) * 43758.5453);
}

void start() {
	CUSTOM.x = h1(float(INDEX) + 0.7);
}

void process() {
	float i = float(INDEX);
	vec3 o = (vec3(h1(i + 0.1), h1(i + 0.2), h1(i + 0.3)) - 0.5) * vec3(spread, spread * 0.45, spread * 2.5);
	float a = TIME * speed + o.z / radius + 0.15 * sin(TIME * 0.21 + i);
	float r = radius + o.x + sin(TIME * 0.3 + i * 1.7) * spread * 0.15;
	float yy = o.y + sin(a * 2.0 + TIME * 0.2) * bob;
	vec3 pos = vec3(cos(a) * r, yy, sin(a) * r);
	vec3 fwd = normalize(vec3(-sin(a), 0.12 * cos(a * 2.0 + TIME * 0.2), cos(a)) * sign(speed));
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 right = normalize(cross(up, fwd));
	up = cross(fwd, right);
	float sc = size * (0.75 + 0.5 * h1(i + 0.9));
	TRANSFORM = mat4(vec4(right * sc, 0.0), vec4(up * sc, 0.0), vec4(fwd * sc, 0.0), vec4(pos, 1.0));
	CUSTOM.x = h1(i + 0.7);
}
