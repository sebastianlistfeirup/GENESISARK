shader_type canvas_item;
// Star-map backdrop (D-046): the painted nebula of nebula_sky.gdshader flattened
// for a 2D galaxy map, after the POLYGON Sci-Fi Space key art and the owner's
// Mass Effect / No Man's Sky bar: violet banks with pink rims, teal pockets,
// dust lanes, a warm glow around the home star, three star layers with a slow
// parallax drift (still with reduced motion) and a faint navigation grid of
// rings and spokes around the map centre. Own art (no vendor data).
uniform vec3 base_color : source_color = vec3(0.03, 0.02, 0.09);
uniform vec3 veil_a : source_color = vec3(0.42, 0.12, 0.66);
uniform vec3 veil_c : source_color = vec3(0.95, 0.3, 0.6);
uniform vec3 veil_b : source_color = vec3(0.07, 0.46, 0.56);
uniform vec3 glow_color : source_color = vec3(1.0, 0.55, 0.2);
uniform vec3 grid_color : source_color = vec3(0.45, 0.9, 0.95);
uniform vec2 aspect = vec2(1.0, 1.0);   // control size / min side, set by the view
uniform vec2 sun_uv = vec2(0.5, 0.5);   // the warm glow's centre in UV
uniform float veil_strength = 0.85;
uniform float drift = 0.004;            // parallax speed (0 with reduced motion)
uniform float grid = 0.22;              // grid line strength
uniform float seed = 3.0;
uniform vec2 parallax = vec2(0.0);      // D-055: pointer parallax, layers move by depth

float hash(vec2 p) { vec3 p3 = fract(vec3(p.xyx + seed * 0.37) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float noise(vec2 x) {
	vec2 i = floor(x); vec2 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 6; i++) { v += a * noise(p); p = p * 2.07 + vec2(1.7, 9.2); a *= 0.5; } return v; }

vec3 stars(vec2 p, float cells, float density, float size, float bright) {
	vec2 q = p * cells;
	vec2 c = floor(q);
	float h = hash(c + 3.1);
	if (h > density) { return vec3(0.0); }
	vec2 centre = c + 0.2 + 0.6 * vec2(hash(c + 9.7), hash(c + 4.3));
	float d = length(q - centre);
	float core = smoothstep(size, 0.0, d);
	float halo = smoothstep(size * 4.0, 0.0, d) * 0.22;
	float pick = hash(c + 21.0);
	vec3 tint = pick < 0.3 ? vec3(0.62, 0.8, 1.0) : (pick < 0.45 ? vec3(1.0, 0.75, 0.5) : (pick < 0.55 ? vec3(1.0, 0.55, 0.85) : vec3(1.0)));
	return tint * (core + halo) * bright * (0.4 + hash(c + 7.0));
}

void fragment() {
	vec2 p0 = (UV - 0.5) * aspect;
	vec2 p = p0 + parallax * 0.35;  // the gas sits far back
	float t = TIME * drift;
	vec2 q = p * 2.2 + vec2(seed * 0.31, seed * 0.17) + vec2(t * 0.3, 0.0);
	float w1 = fbm(q);
	float w2 = fbm(q * 1.8 + vec2(4.0, seed) + w1 * 1.5);
	float teal = fbm(p * 3.0 + vec2(17.0, 3.0) + w2 * 0.9);
	float detail = fbm(p * 8.0 + w2 * 2.0 + 9.0);
	vec3 col = base_color;
	float banks = smoothstep(0.36, 0.84, w2);
	col += veil_a * banks * 1.1 * veil_strength;
	col += veil_c * smoothstep(0.6, 0.9, w2) * (0.5 + 0.6 * detail) * veil_strength;
	col += veil_b * smoothstep(0.56, 0.86, teal) * (1.0 - banks * 0.6) * veil_strength;
	// warm glow of the home star
	vec2 sp = (sun_uv - 0.5) * aspect;
	float sd = length(p - sp);
	col = mix(col, glow_color * (0.7 + detail * 0.8), smoothstep(0.42, 0.0, sd) * 0.45 * (0.6 + w2 * 0.6));
	col += vec3(1.0, 0.85, 0.6) * smoothstep(0.05, 0.0, sd) * 0.9;
	// dust lanes
	col *= mix(1.0, 0.45, smoothstep(0.55, 0.78, fbm(p * 5.0 + 23.0 + w1)));
	// stars, each layer drifting at its own speed
	col += stars(p0 + parallax * 0.5 + vec2(t * 0.2, 0.0), 160.0, 0.05 + 0.06 * banks, 0.22, 0.7);
	col += stars(p0 + parallax * 1.0 + vec2(t * 0.5, 0.0), 60.0, 0.05, 0.12, 1.6);
	col += stars(p0 + parallax * 1.8 + vec2(t * 1.0, 0.0), 22.0, 0.04, 0.07, 3.0);
	// navigation grid: rings and spokes around the centre, fading outwards (fixed to the map)
	p = p0;
	float r = length(p);
	float ring = smoothstep(0.0035, 0.0, abs(fract(r * 6.0 + 0.5) - 0.5) / 6.0);
	float ang = atan(p.y, p.x) / 6.2831853 * 12.0;
	float spoke = smoothstep(0.012, 0.0, abs(fract(ang + 0.5) - 0.5) * r * 0.55) * smoothstep(0.06, 0.12, r);
	float g = max(ring, spoke * 0.6) * smoothstep(0.75, 0.15, r);
	col += grid_color * g * grid;
	COLOR = vec4(col, 1.0);
}
