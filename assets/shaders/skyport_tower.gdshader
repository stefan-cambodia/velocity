// Cirrus Heights towers: warm white stone with glass. UV = facade metres
// (u around, v down the face). COLOR.rgb = stone tint, COLOR.a = style:
// 0 plain stone (roofs, plinths, decks), 0.5 ribbon windows, 1 glass curtain
// wall with mullions. The glass is a smooth blue-grey half mirror that picks
// up the pastel sky from the environment's radiance map; ribbon windows are
// broken by a stone pier every third bay. Bands fade to their average with
// distance so far towers do not shimmer.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform float floor_h = 4.2;
uniform float bay_w = 2.6;
uniform vec3 glass_col : source_color = vec3(0.42, 0.48, 0.62);
uniform bool plain = false;            // piers and girders: stone only
uniform float cloud_y = 10.0;          // the sea of clouds
uniform vec3 mist_col : source_color = vec3(0.8, 0.7, 0.8);

varying vec3 wn;
varying float world_y;

void vertex() {
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float style = plain ? 0.0 : COLOR.a;
	float vertical = 1.0 - smoothstep(0.4, 0.6, abs(normalize(wn).y));
	float fy = UV.y / floor_h;
	float fx = UV.x / bay_w;
	float wy = clamp(fwidth(fy), 0.001, 1.0);
	float wx = clamp(fwidth(fx), 0.001, 1.0);
	float sill = mix(0.42, 0.85, step(0.75, style));
	// Anti-aliased bands, blending to the mean coverage when a floor is under ~2 px.
	float band = smoothstep(sill + wy, sill - wy, fract(fy)) * smoothstep(0.0, wy * 2.0, fract(fy));
	band = mix(band, sill, smoothstep(0.25, 0.5, wy));
	float mull = step(0.75, style) * smoothstep(0.07 + wx, 0.07 - wx, fract(fx));
	mull = mix(mull, 0.07 * step(0.75, style), smoothstep(0.25, 0.5, wx));
	// Ribbon-window towers: a stone pier every third bay breaks the bands into a grid.
	float fp = UV.x / (bay_w * 3.0);
	float wp = clamp(fwidth(fp), 0.001, 1.0);
	float pier = (1.0 - step(0.75, style)) * smoothstep(0.16 + wp, 0.16 - wp, fract(fp));
	pier = mix(pier, 0.16 * (1.0 - step(0.75, style)), smoothstep(0.25, 0.5, wp));
	float glass = step(0.25, style) * vertical * band * (1.0 - mull) * (1.0 - pier);
	// The foot of every tower and pier disappears into mist above the cloud tops.
	float mist = 1.0 - smoothstep(cloud_y - 2.0, cloud_y + 30.0, world_y);
	ALBEDO = mix(mix(COLOR.rgb, glass_col, glass), mist_col * 0.5, mist);
	ROUGHNESS = mix(mix(0.78, 0.12, glass), 1.0, mist);
	METALLIC = mix(0.0, 0.65, glass) * (1.0 - mist);
	SPECULAR = mix(0.4, 0.8, glass) * (1.0 - mist);
	EMISSION = mist_col * mist * 0.55;
}
