shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;
// Aurora curtain: vertical rays drifting along a ring high in the sky, green at
// the foot, violet at the top, fading at both edges. Own art.
uniform vec3 low_color : source_color = vec3(0.2, 1.0, 0.6);
uniform vec3 high_color : source_color = vec3(0.6, 0.3, 1.0);
uniform float strength = 1.0;
uniform float speed = 0.02;

float h1(float x) { return fract(sin(x * 127.1) * 43758.5453); }
float n1(float x) { float i = floor(x); float f = fract(x); f = f * f * (3.0 - 2.0 * f); return mix(h1(i), h1(i + 1.0), f); }

void fragment() {
	float x = UV.x * 40.0 + TIME * speed * 40.0;
	float rays = n1(x * 3.0) * 0.6 + n1(x * 11.0 + 5.0) * 0.4;
	float sweep = smoothstep(0.25, 0.75, n1(UV.x * 7.0 + TIME * speed * 3.0));
	float v = UV.y;
	float body = smoothstep(0.0, 0.25, 1.0 - v) * smoothstep(1.0, 0.55, 1.0 - v);
	vec3 col = mix(low_color, high_color, clamp(1.0 - v, 0.0, 1.0));
	ALBEDO = col * rays * sweep * body * strength;
}
