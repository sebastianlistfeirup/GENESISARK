shader_type sky;
// Painted-space sky after the POLYGON Sci-Fi Space key art: deep violet base,
// teal and magenta nebula veils, a warm glow toward the key light and a fine
// star field. Own art (no vendor data).
uniform vec3 base_color : source_color = vec3(0.035, 0.02, 0.08);
uniform vec3 veil_a : source_color = vec3(0.42, 0.12, 0.55);
uniform vec3 veil_b : source_color = vec3(0.08, 0.38, 0.45);
uniform vec3 glow_color : source_color = vec3(1.0, 0.55, 0.25);
uniform float veil_strength = 1.0;
uniform float seed = 0.0;

float hash(vec3 p3) { p3 = fract((p3 + seed * 0.731) * 0.1031); p3 += dot(p3, p3.zyx + 31.32); return fract((p3.x + p3.y) * p3.z); }
float noise(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 6; i++) { v += a * noise(p); p *= 2.1; a *= 0.5; } return v; }

void sky() {
	vec3 d = EYEDIR;
	float n1 = fbm(d * 2.2 + vec3(seed));
	float n2 = fbm(d * 3.7 + vec3(4.0, seed, 1.0) + n1 * 1.5);
	vec3 col = base_color;
	col += veil_a * smoothstep(0.42, 0.85, n1) * 0.9 * veil_strength;
	col += veil_b * smoothstep(0.5, 0.9, n2) * 0.8 * veil_strength;
	// dark dust lanes cut through the veils
	col *= mix(1.0, 0.45, smoothstep(0.55, 0.8, fbm(d * 6.0 + 9.0)));
	// warm glow toward the key light (the system's star)
	float sun_dot = max(dot(d, LIGHT0_DIRECTION), 0.0);
	col += glow_color * (pow(sun_dot, 6.0) * 0.55 + pow(sun_dot, 64.0) * 1.6) * (LIGHT0_ENABLED ? 1.0 : 0.0);
	// stars: sparse bright points, denser where the veils are
	vec3 sp = d * 420.0;
	float st = hash(floor(sp));
	float star = step(0.9975 - 0.0015 * smoothstep(0.4, 0.8, n1), st) * smoothstep(0.45, 0.0, length(fract(sp) - 0.5));
	col += vec3(0.9, 0.92, 1.0) * star * 1.6;
	COLOR = col;
}
