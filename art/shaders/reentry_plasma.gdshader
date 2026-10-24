shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled;
// Atmospheric entry around the lander: a stretched shell that burns at the
// leading edge (fresnel, brightest where it faces the direction of travel) and
// streams into a flickering tail behind it. `heat` 0..1 drives it all. Own art.
uniform float heat = 0.0;
uniform vec3 hot : source_color = vec3(1.0, 0.86, 0.6);
uniform vec3 warm : source_color = vec3(1.0, 0.42, 0.12);
uniform vec3 cool : source_color = vec3(0.55, 0.3, 1.0);

varying vec3 lp;

float h(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float n2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 1.6);
	// -Z is the nose (direction of travel): front burns white-hot, the tail cools.
	float front = clamp(-lp.z * 0.5 + 0.5, 0.0, 1.0);
	float flick = n2(vec2(lp.x * 3.0 + TIME * 9.0, lp.z * 2.0 - TIME * 24.0));
	float streak = n2(vec2(atan(lp.y, lp.x) * 4.0, lp.z * 1.5 - TIME * 30.0));
	vec3 col = mix(cool, warm, smoothstep(0.1, 0.6, front));
	col = mix(col, hot, smoothstep(0.7, 1.0, front));
	if (front < 0.42) { discard; }  // nose cap only: the tail is the streaks' job
	float a = (fres * 0.85 + front * front * 0.6) * (0.55 + 0.45 * flick) * (0.6 + 0.6 * streak);
	ALBEDO = col * a * heat * 2.2;
}
