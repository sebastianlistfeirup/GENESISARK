shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
// Godot take on the POLYGON Nature Biomes foliage shader: one mesh carries both
// leaves and trunk; vertex colour blue marks leaves (1) vs trunk (0). Leaves are
// alpha-cut, tinted per planet (hue/saturation/value), sway in the wind; the
// trunk is opaque bark. Optional glow on the leaves for bioluminescent worlds.
uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D trunk_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_trunk = true;
uniform vec3 leaf_tint : source_color = vec3(1.0);
uniform vec3 trunk_tint : source_color = vec3(1.0);
uniform float hue_shift = 0.0;
uniform float sat_mul = 1.0;
uniform float alpha_cut = 0.45;
uniform float wind = 0.06;
uniform float glow = 0.0;
uniform vec3 glow_color : source_color = vec3(0.3, 1.0, 0.8);
uniform float near_fade_start = 1.2;  // metres from the camera: foliage dithers away
uniform float near_fade_end = 3.2;    // so it never fills the screen in front of the captain

varying float leaf_mask;

vec3 hsv_shift(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	vec3 hsv = vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
	hsv.x = fract(hsv.x + hue_shift);
	hsv.y = clamp(hsv.y * sat_mul, 0.0, 1.0);
	vec3 rgb = clamp(abs(mod(hsv.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return hsv.z * mix(vec3(1.0), rgb, hsv.y);
}

void vertex() {
	leaf_mask = has_trunk ? step(0.5, COLOR.b) : 1.0;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = sin(TIME * 1.7 + wp.x * 0.35 + wp.z * 0.27) + 0.4 * sin(TIME * 3.1 + wp.z * 0.9);
	VERTEX.xz += vec2(sway, sway * 0.6) * wind * leaf_mask * max(VERTEX.y, 0.0) * 0.12;
}

void fragment() {
	vec4 lc = texture(leaf_tex, UV);
	vec3 tc = texture(trunk_tex, UV).rgb;
	vec3 leaf = hsv_shift(lc.rgb) * leaf_tint;
	ALBEDO = mix(tc * trunk_tint, leaf, leaf_mask);
	if (leaf_mask > 0.5 && lc.a < alpha_cut) {
		discard;
	}
	float cam_d = length(VERTEX);
	float keep = smoothstep(near_fade_start, near_fade_end, cam_d);
	float bayer = fract(dot(floor(FRAGCOORD.xy), vec2(0.5, 0.25)) + fract(FRAGCOORD.y * 0.5) * 0.5);
	if (keep < 0.999 && bayer > keep) {
		discard;
	}
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	EMISSION = leaf * glow_color * glow * leaf_mask;
	BACKLIGHT = vec3(0.25) * leaf_mask;
}
