shader_type sky;
// Painted-space sky after the POLYGON Sci-Fi Space key art (D-036, regraded in
// D-044 after the owner's reference sheet): a sky full of glowing nebula, not a
// black void. Violet-magenta cloud banks with pink rims, teal pockets, a fiery
// orange-gold region around the system's sun, dark dust lanes, a white-hot sun
// disc with halo and a horizontal lens streak, and a dense star field with big
// coloured stars. Own art (no vendor data).
uniform vec3 base_color : source_color = vec3(0.045, 0.03, 0.13);
uniform vec3 veil_a : source_color = vec3(0.46, 0.13, 0.7);    // violet cloud banks
uniform vec3 veil_c : source_color = vec3(1.0, 0.3, 0.62);     // magenta-pink rims
uniform vec3 veil_b : source_color = vec3(0.08, 0.5, 0.6);     // teal pockets
uniform vec3 glow_color : source_color = vec3(1.0, 0.5, 0.14); // fiery region near the sun
uniform vec3 core_color : source_color = vec3(1.0, 0.86, 0.45);
uniform float veil_strength = 1.0;
uniform float warm_reach = 0.6;   // how far the orange-gold region spreads from the sun
uniform float sun_size = 0.018;   // radians
uniform float sun_energy = 14.0;
uniform float star_boost = 1.0;
uniform float seed = 0.0;

float hash(vec3 p3) { p3 = fract((p3 + seed * 0.731) * 0.1031); p3 += dot(p3, p3.zyx + 31.32); return fract((p3.x + p3.y) * p3.z); }
vec3 hash3(vec3 p) { return vec3(hash(p), hash(p + 17.31), hash(p + 41.7)); }
float noise(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 6; i++) { v += a * noise(p); p *= 2.1; a *= 0.5; } return v; }

// One star layer: cells on the sphere, a random point per cell, soft round dots.
vec3 stars(vec3 d, float cells, float density, float size, float bright, float colored) {
	vec3 p = d * cells;
	vec3 c = floor(p);
	vec3 h = hash3(c + 3.1);
	if (h.x > density) { return vec3(0.0); }
	vec3 centre = c + 0.2 + 0.6 * hash3(c + 9.7);
	float dist = length(p - centre);
	float core = smoothstep(size, 0.0, dist);
	float halo = smoothstep(size * 4.0, 0.0, dist) * 0.25;
	vec3 tint = vec3(1.0);
	float pick = h.y;
	if (pick < 0.3) { tint = vec3(0.6, 0.78, 1.0); }
	else if (pick < 0.48) { tint = vec3(1.0, 0.72, 0.45); }
	else if (pick < 0.6) { tint = vec3(1.0, 0.5, 0.85); }
	tint = mix(vec3(1.0), tint, colored);
	return tint * (core + halo) * bright * (0.5 + h.z);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	// Domain-warped cloud fields: soft, billowing banks like the painted key art.
	vec3 q = d * 1.7 + vec3(seed * 0.37);
	float w1 = fbm(q);
	float w2 = fbm(q * 1.9 + vec3(4.0, seed, 1.0) + w1 * 1.6);
	float n_teal = fbm(d * 2.4 + vec3(17.0, 3.0, seed) + w2 * 0.9);
	float detail = fbm(d * 7.0 + w2 * 2.0 + 9.0);
	float sun_on = LIGHT0_ENABLED ? 1.0 : 0.0;
	vec3 sd = LIGHT0_DIRECTION;
	float sun_dot = max(dot(d, sd), 0.0) * sun_on;

	vec3 col = base_color;
	float banks = smoothstep(0.34, 0.82, w2);
	col += veil_a * banks * 1.25 * veil_strength;
	// pink rims where banks are densest, lit edges in the detail noise
	col += veil_c * smoothstep(0.58, 0.9, w2) * (0.55 + 0.6 * detail) * veil_strength;
	col += veil_b * smoothstep(0.55, 0.85, n_teal) * (1.0 - banks * 0.6) * 1.1 * veil_strength;
	// fiery orange-gold clouds around the sun (image1's left side)
	float warm = pow(sun_dot, 3.0 / max(warm_reach, 0.05));
	float fire = smoothstep(0.15, 0.95, warm * (0.55 + w2 * 0.9 + detail * 0.35));
	col = mix(col, glow_color * (0.8 + detail), fire * 0.8);
	col += core_color * pow(sun_dot, 32.0) * 1.1;
	// dark dust lanes through the banks
	col *= mix(1.0, 0.38, smoothstep(0.56, 0.78, fbm(d * 5.0 + 23.0 + w1)) * (1.0 - fire * 0.7));
	// sun: white-hot disc, halo and a horizontal anamorphic streak
	float ang = acos(clamp(dot(d, sd), -1.0, 1.0));
	float disc = smoothstep(sun_size, sun_size * 0.7, ang) * sun_on;
	col += vec3(1.0, 0.95, 0.85) * disc * sun_energy;
	col += vec3(1.0, 0.8, 0.55) * pow(sun_dot, 400.0) * 3.0;
	vec3 up = abs(sd.y) > 0.95 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
	vec3 side = normalize(cross(up, sd));
	vec3 vert = cross(sd, side);
	vec3 rel = d - sd * dot(d, sd);
	float sx = dot(rel, side);
	float sy = dot(rel, vert);
	float streak = exp(-abs(sy) * 260.0) * exp(-abs(sx) * 4.5) * step(0.0, dot(d, sd));
	col += vec3(1.0, 0.75, 0.5) * streak * 1.6 * sun_on;
	// stars: fine dense dust, mid stars, a few big coloured ones (bloom picks them up)
	col += stars(d, 520.0, 0.025 + 0.035 * banks, 0.2, 1.0, 0.4) * star_boost;
	col += stars(d, 190.0, 0.03, 0.15, 2.6, 0.8) * star_boost;
	col += stars(d, 70.0, 0.02, 0.07, 8.0, 1.0) * star_boost;
	COLOR = col;
}
