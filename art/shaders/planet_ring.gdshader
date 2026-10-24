shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
// Planetary ring on a flat quad: concentric bands with gaps, fading at the
// inner and outer edge. Own art (no vendor data).
uniform vec3 ring_color : source_color = vec3(0.9, 0.78, 0.62);
uniform vec3 band_color : source_color = vec3(0.62, 0.48, 0.4);
uniform float inner = 0.42;
uniform float outer = 0.98;
uniform float opacity = 0.75;
uniform float seed = 3.0;

float h1(float x) { return fract(sin(x * 91.17 + seed) * 43758.5453); }
float n1(float x) { float i = floor(x); float f = fract(x); f = f * f * (3.0 - 2.0 * f); return mix(h1(i), h1(i + 1.0), f); }

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float t = (r - inner) / (outer - inner);
	if (t < 0.0 || t > 1.0) { discard; }
	float bands = n1(t * 38.0) * 0.6 + n1(t * 9.0) * 0.4;
	float gap = smoothstep(0.52, 0.55, t) * (1.0 - smoothstep(0.58, 0.61, t));
	float edge = smoothstep(0.0, 0.06, t) * (1.0 - smoothstep(0.9, 1.0, t));
	vec3 col = mix(band_color, ring_color, bands);
	ALBEDO = col;
	ALPHA = clamp(edge * (0.35 + 0.65 * bands) * (1.0 - gap * 0.85) * opacity, 0.0, 1.0);
}
