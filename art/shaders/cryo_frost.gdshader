shader_type canvas_item;
// Frosted cryo-pod glass seen from inside: crystalline frost thick at the edges,
// a breath-cleared patch in the middle, hairline cracks before the hatch opens,
// slides up out of view with `slide`. Own art.
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform float crack : hint_range(0.0, 1.0) = 0.0;
uniform float slide = 0.0;       // 0 = closed, 1 = hatch fully up
uniform float breath = 0.0;      // 0..1 pulse that clears the middle a little
uniform vec4 tint : source_color = vec4(0.72, 0.86, 0.95, 1.0);

// Sine-free hash: the old fract(sin()) one lost precision on the fine frost octaves
// (inputs in the hundreds) and broke the glass into rectangular blocks.
float h(vec2 p) { vec3 q = fract(vec3(p.xyx) * 0.1031); q += dot(q, q.yzx + 33.33); return fract((q.x + q.y) * q.z); }
float n(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 5; i++) { v += n(p) * a; p *= 2.07; a *= 0.5; } return v; }

void fragment() {
	vec2 uv = UV + vec2(0.0, slide * 1.15);
	if (uv.y > 1.0) { discard; }
	vec2 c = uv - vec2(0.5, 0.52);
	c.x *= 1.6;
	float edge = smoothstep(0.18 + breath * 0.06, 0.75, length(c));
	float frost = fbm(uv * vec2(9.0, 6.0)) * 0.6 + fbm(uv * 38.0) * 0.4;
	// Fern-like crystal streaks growing in from the frame.
	float streak = smoothstep(0.55, 0.9, fbm(vec2(atan(c.y, c.x) * 3.0, length(c) * 14.0)));
	float a = clamp(edge * (0.55 + frost * 0.6) + streak * edge * 0.4, 0.0, 1.0);
	a = mix(a, max(a, 0.35), 0.5);
	// Cracks: thin bright lines from a point low-left.
	float cl = 0.0;
	if (crack > 0.0) {
		vec2 q = uv - vec2(0.34, 0.68);
		float ang = atan(q.y, q.x);
		float rays = abs(sin(ang * 5.0 + fbm(q * 6.0) * 4.0));
		cl = smoothstep(0.012, 0.0, rays * length(q)) * step(length(q), crack * 0.55) * 0.55;
	}
	vec3 col = mix(tint.rgb * 0.55, tint.rgb, frost);
	col += vec3(cl) * 0.9;
	// The hatch frame edge as it slides up.
	float rim = smoothstep(0.985, 1.0, uv.y) * step(0.001, slide);
	col = mix(col, vec3(0.08, 0.1, 0.12), rim);
	COLOR = vec4(col, clamp(a * amount + cl + rim, 0.0, 1.0));
}
