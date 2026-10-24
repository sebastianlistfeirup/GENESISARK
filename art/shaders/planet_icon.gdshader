shader_type canvas_item;
// A small lit planet for 2D maps: sphere from UV, fbm continents/dunes/ice in
// the planet's colours, soft terminator and an atmosphere rim. Own art.
uniform vec4 base_color : source_color = vec4(0.31, 0.54, 0.35, 1.0);
uniform vec4 ocean_color : source_color = vec4(0.07, 0.22, 0.38, 1.0);
uniform vec4 high_color : source_color = vec4(0.85, 0.85, 0.8, 1.0);
uniform vec4 atmo_color : source_color = vec4(0.45, 0.7, 1.0, 1.0);
uniform float sea_level = 0.48;
uniform float banding = 0.0;
uniform float seed = 0.0;
uniform float spin = 0.02;

float hash(vec3 p3) { p3 = fract((p3 + seed * 0.731) * 0.1031); p3 += dot(p3, p3.zyx + 31.32); return fract((p3.x + p3.y) * p3.z); }
float noise(vec3 x) { vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z); }
float fbm(vec3 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; } return v; }

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float r2 = dot(q, q);
	if (r2 > 1.0) {
		float halo = smoothstep(1.25, 1.0, sqrt(r2));
		COLOR = vec4(atmo_color.rgb, halo * 0.35);
	} else {
		vec3 n = vec3(q.x, -q.y, sqrt(1.0 - r2));
		float a = TIME * spin;
		vec3 m = vec3(n.x * cos(a) - n.z * sin(a), n.y, n.x * sin(a) + n.z * cos(a));
		float h = fbm(m * 2.4 + seed);
		h = mix(h, h * 0.6 + 0.4 * (0.5 + 0.5 * sin(m.y * 16.0 + h * 6.0)), banding);
		float land = smoothstep(sea_level - 0.02, sea_level + 0.02, h);
		vec3 col = mix(ocean_color.rgb, base_color.rgb * (0.8 + 0.4 * fbm(m * 8.0)), land);
		col = mix(col, high_color.rgb, smoothstep(sea_level + 0.17, sea_level + 0.27, h));
		col = mix(col, vec3(0.95), smoothstep(0.78, 0.92, abs(m.y)));
		float lit = clamp(dot(n, normalize(vec3(-0.5, 0.45, 0.75))), 0.0, 1.0);
		col *= 0.18 + 0.95 * lit;
		col += atmo_color.rgb * pow(1.0 - n.z, 3.0) * 0.8;
		COLOR = vec4(col, smoothstep(1.0, 0.97, r2));
	}
}
