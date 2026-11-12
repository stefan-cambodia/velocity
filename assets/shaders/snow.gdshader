// Snowfields and mountains: soft white snow with blue shading and sparkle on
// gentle slopes, dark rock and blue ice on steep faces.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 snow : source_color = vec3(0.86, 0.9, 0.96);
uniform vec3 snow_shadow : source_color = vec3(0.55, 0.65, 0.82);
uniform vec3 rock : source_color = vec3(0.12, 0.13, 0.16);
uniform vec3 ice : source_color = vec3(0.4, 0.7, 0.9);

varying vec3 wpos;
varying vec3 wn;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);
	float rocky = smoothstep(0.38, 0.55, slope + (hash(floor(wpos.xz / 6.0)) - 0.5) * 0.12);
	float icy = smoothstep(0.25, 0.4, slope) * (1.0 - rocky) * 0.6;
	vec3 base = mix(snow, snow_shadow, smoothstep(0.1, 0.4, slope) * 0.5);
	base = mix(base, ice, icy);
	base = mix(base, rock, rocky);
	ALBEDO = base * COLOR.rgb;
	ROUGHNESS = mix(0.55, 0.85, rocky);
	SPECULAR = 0.4;
	float sparkle = step(0.997, hash(floor(wpos.xz * 3.0) + floor(TIME * 2.0))) * (1.0 - rocky);
	EMISSION = vec3(sparkle) * 0.6;
}
