shader_type spatial;
// Hazard zone ground decal (D-043): a disc draped on the faceted terrain.
// UV.x = arc length (m) along the edge circle, UV.y = distance (m) from the
// zone centre. Layers: faint noisy interior tint, an inward pulse, a band of
// diagonal hazard-tape stripes just inside the edge (shape cue, not colour
// alone) and a bright edge line with a soft halo. Unshaded so it reads at
// night and through fog; the zone colour carries the hazard type.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 zone_color : source_color = vec4(0.84, 0.77, 0.28, 1.0);
uniform float radius = 10.0;
uniform float glow = 1.6;
uniform float motion = 1.0;          // 0 with reduced motion: no pulse, still stripes
uniform float interior_alpha = 0.10;
uniform vec4 interior_color : source_color = vec4(0.84, 0.77, 0.28, 1.0);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Pull a little toward the camera so terrain facet creases never cut the decal.
	vec3 vv = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vv += normalize(-vv) * 0.14;
	POSITION = PROJECTION_MATRIX * vec4(vv, 1.0);
}

vec4 over(vec4 dst, vec3 c, float a) {
	// premultiplied "over"
	return vec4(c * a + dst.rgb * (1.0 - a), a + dst.a * (1.0 - a));
}

void fragment() {
	float d = UV.y;
	float e = radius - d;               // > 0 inside the zone
	float arc = UV.x;
	float t = TIME * motion;
	vec3 col = zone_color.rgb;
	float n = texture(noise_tex, wpos.xz * 0.045 + vec2(t * 0.006, 0.0)).r;
	float n2 = texture(noise_tex, wpos.xz * 0.11 - vec2(0.0, t * 0.01)).r;
	vec4 acc = vec4(0.0);
	// interior tint: denser toward the edge, broken up by noise
	float inside = smoothstep(-0.05, 0.4, e);
	float ia = interior_alpha * inside * (0.45 + 0.9 * n * n2) * (0.55 + 0.45 * exp(-e / 3.0));
	acc = over(acc, interior_color.rgb * 0.8, ia);
	// inward pulse every ~4.5 s
	float p = fract(t * 0.22);
	float reach = min(radius * 0.7, 7.0);
	float wq = (e - 1.8 - p * reach) / 0.45;
	float wave = exp(-wq * wq) * (1.0 - p) * 0.28 * step(0.001, motion);
	acc = over(acc, col * glow, wave * inside);
	// hazard-tape band: alternating bright/dark diagonal stripes
	float band = smoothstep(0.38, 0.5, e) * (1.0 - smoothstep(1.55, 1.7, e));
	float s = fract((arc + e) * 0.62 - t * 0.12);
	float aa = fwidth(s) * 1.5 + 0.02;
	float st = smoothstep(0.5 - aa, 0.5 + aa, s) * (1.0 - smoothstep(1.0 - aa, 1.0, s)) + (1.0 - smoothstep(0.0, aa, s));
	st = clamp(st, 0.0, 1.0);
	vec3 bandc = mix(col * 0.08, col * 1.05, st);
	acc = over(acc, bandc, band * mix(0.5, 0.85, st));
	// soft halo both sides of the line
	float halo = exp(-abs(e - 0.2) * 2.0) * 0.42;
	acc = over(acc, col * glow, halo * smoothstep(-1.2, 0.0, e));
	// bright edge line (with a hint of white in its core)
	float core = 1.0 - smoothstep(0.1, 0.26, abs(e - 0.2));
	acc = over(acc, mix(col, vec3(1.0), 0.3) * glow, core * 0.95);
	ALBEDO = acc.a > 0.0001 ? acc.rgb / acc.a : col;
	ALPHA = clamp(acc.a, 0.0, 1.0);
}
