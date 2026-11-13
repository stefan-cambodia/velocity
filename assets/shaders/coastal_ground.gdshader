// Costa Branca terrain: pale limestone with strata on steep faces, golden sand
// at the waterline (darker where wet), sun-dried grass and green scrub on the
// slopes, red-brown soil in the olive groves. Variation comes from a baked
// noise texture (coastal_noise.png: R coarse, G medium, B fine), not per-pixel
// noise. COLOR.r = olive grove soil weight, COLOR.g = town paving weight.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec3 sand : source_color = vec3(0.9, 0.8, 0.6);
uniform vec3 wet_sand : source_color = vec3(0.66, 0.56, 0.4);
uniform vec3 grass : source_color = vec3(0.56, 0.5, 0.33);
uniform vec3 garrigue : source_color = vec3(0.38, 0.4, 0.26);
uniform vec3 scrub : source_color = vec3(0.19, 0.25, 0.13);
uniform vec3 soil : source_color = vec3(0.5, 0.42, 0.33);
uniform vec3 rock_a : source_color = vec3(0.8, 0.76, 0.66);
uniform vec3 rock_b : source_color = vec3(0.64, 0.6, 0.52);
uniform vec3 paving : source_color = vec3(0.78, 0.74, 0.66);
uniform float sea_y = 0.0;

varying vec3 wpos;
varying vec3 wn;
varying vec2 extra;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	extra = COLOR.rg;
}

void fragment() {
	vec3 nz = texture(noise_tex, wpos.xz * 0.0011).rgb;
	vec3 nf = texture(noise_tex, wpos.xz * 0.019).rgb;
	float fade = clamp(1.0 - length(fwidth(wpos.xz)) * 0.35, 0.0, 1.0);
	// Steepness from the facet as well as the smooth normal, so cliffs read as rock.
	vec3 fn = normalize(cross(dFdx(wpos), dFdy(wpos)));
	float slope = max(1.0 - clamp(normalize(wn).y, 0.0, 1.0), (1.0 - abs(fn.y)) * 0.95);
	float y = wpos.y - sea_y;
	// Slopes: dry grass with patches of dark scrub (maquis).
	float patches = smoothstep(0.38, 0.6, nz.r * 0.6 + nf.g * 0.4);
	vec3 dry = mix(grass * (0.85 + 0.3 * nz.g), garrigue, smoothstep(0.3, 0.7, nz.b * 0.5 + nf.r * 0.5));
	vec3 land = mix(dry, scrub * (0.8 + 0.4 * nf.r), patches);
	land *= 0.9 + 0.2 * mix(0.5, nf.b, fade);
	// Olive groves: ploughed red-brown soil between the trees.
	land = mix(land, soil * (0.85 + 0.3 * nf.g), clamp(extra.r, 0.0, 1.0) * (0.6 + 0.4 * nz.b));
	// Town: worn paving and packed earth.
	land = mix(land, paving * (0.88 + 0.2 * nf.r), clamp(extra.g, 0.0, 1.0));
	// Beach sand near the water on gentle ground, wet at the waterline.
	float beach = (1.0 - smoothstep(2.2, 4.5, y + nf.r * 1.5)) * (1.0 - smoothstep(0.12, 0.35, slope));
	vec3 sandc = mix(sand * (0.92 + 0.12 * nf.b), wet_sand, 1.0 - smoothstep(0.1, 0.9, y));
	vec3 col = mix(land, sandc, beach);
	// Limestone on steep faces, banded with strata, pale and sunlit.
	float rocky = smoothstep(0.32, 0.55, slope + (nf.g - 0.5) * 0.25);
	float band = sin(wpos.y * 0.75 + nz.g * 7.0) * 0.5 + 0.5;
	float seam = smoothstep(0.9, 0.98, sin(wpos.y * 0.31 + nf.r * 3.0) * 0.5 + 0.5);
	vec3 rock = mix(rock_b, rock_a, band * 0.7 + nf.b * 0.3 * fade) * (1.0 - seam * 0.25);
	col = mix(col, rock, rocky);
	// Algae-darkened rock just above the water.
	col *= 1.0 - (1.0 - smoothstep(0.0, 1.6, y)) * rocky * 0.45;
	ALBEDO = col;
	ROUGHNESS = mix(0.92, 0.75, rocky);
	SPECULAR = 0.3;
}
