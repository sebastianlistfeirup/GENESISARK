shader_type spatial;
render_mode fog_disabled;
// Procedural planet: fbm continents/dunes/ice in object space, a slowly drifting
// cloud layer, terminator softening and an atmosphere rim. Own art (no vendor data).
uniform vec3 base_color : source_color = vec3(0.31, 0.54, 0.35);
uniform vec3 ocean_color : source_color = vec3(0.07, 0.22, 0.38);
uniform vec3 high_color : source_color = vec3(0.85, 0.85, 0.8);
uniform vec3 atmo_color : source_color = vec3(0.45, 0.7, 1.0);
uniform float sea_level = 0.48;
uniform float cloud_amount = 0.45;
uniform float banding = 0.0;
uniform float seed = 0.0;
uniform float cloud_speed = 0.004;
uniform float city_lights = 0.0;  // a settled world: warm lights on the night side
uniform vec3 sun_dir = vec3(0.6, 0.3, 0.75);
uniform vec3 settlement = vec3(0.3, 0.35, 0.88);

varying vec3 obj_n;

float hash(vec3 p3) { p3 = fract((p3 + seed * 0.731) * 0.1031); p3 += dot(p3, p3.zyx + 31.32); return fract((p3.x + p3.y) * p3.z); }
float noise(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0,0,0)), hash(i + vec3(1,0,0)), f.x), mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x), mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 6; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; } return v; }

void vertex() { obj_n = normalize(VERTEX); }

void fragment() {
	vec3 n = obj_n;
	float h = fbm(n * 2.6 + seed);
	h = mix(h, h * 0.6 + 0.4 * (0.5 + 0.5 * sin(n.y * 18.0 + h * 6.0)), banding);
	float land = smoothstep(sea_level - 0.015, sea_level + 0.015, h);
	vec3 col = mix(ocean_color, base_color * (0.75 + 0.5 * fbm(n * 9.0 + 3.0)), land);
	float peaks = smoothstep(sea_level + 0.17, sea_level + 0.27, h);
	col = mix(col, high_color, peaks);
	float pole = smoothstep(0.78, 0.92, abs(n.y) + 0.08 * fbm(n * 6.0));
	col = mix(col, vec3(0.93, 0.96, 1.0), pole);
	vec3 cn = n; float a = TIME * cloud_speed; cn.xz = mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a))) * cn.xz;
	float cl = smoothstep(1.0 - cloud_amount, 1.0 - cloud_amount + 0.25, fbm(cn * 4.0 + 11.0));
	col = mix(col, vec3(0.97), cl * 0.85);
	ALBEDO = col;
	ROUGHNESS = mix(0.35, 0.95, land);
	SPECULAR = mix(0.6, 0.2, land);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = atmo_color * rim * 1.4;
	if (city_lights > 0.0) {
		float night = smoothstep(0.05, -0.25, dot(n, normalize(sun_dir)));
		float near = smoothstep(0.86, 0.985, dot(n, normalize(settlement)));
		float dots = step(0.82, hash(floor(n * 160.0))) * land;
		float spread = step(0.93, hash(floor(n * 70.0) + 3.0)) * land * smoothstep(0.6, 0.9, dot(n, normalize(settlement)));
		EMISSION += vec3(1.0, 0.72, 0.35) * (dots * near + spread * 0.6) * night * city_lights * 3.0;
	}
}
