shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
// A floating holographic screen (Sci-Fi Space key art): bright frame, faint fill,
// rows of data bars, a trace graph and a slow scan band. Our own procedural art.
// error = 1: the derelict look on emergency power (red, mostly empty, blinking warning).

uniform vec3 color : source_color = vec3(0.25, 0.95, 1.0);
uniform float energy = 1.6;
uniform float seed = 0.0;
uniform float error = 0.0;
uniform float motion = 1.0;  // 0 with reduced motion: no scan band, no blinking
uniform vec2 aspect = vec2(1.6, 1.0);

float hash(float n) {
	return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453);
}

void fragment() {
	vec2 uv = vec2(UV.x, 1.0 - UV.y);
	vec2 px = uv * aspect;
	float t = TIME * motion;
	// Frame with corner brackets.
	vec2 e = min(px, aspect - px);
	float edge = min(e.x, e.y);
	float frame = smoothstep(0.035, 0.02, edge) * 0.9;
	float corner = step(edge, 0.06) * step(min(max(e.x, e.y), 1.0), 0.22);
	float fill = 0.10;
	float data = 0.0;
	if (error < 0.5) {
		// Header bar.
		data += step(0.82, uv.y) * step(uv.y, 0.9) * step(0.06, uv.x) * step(uv.x, 0.06 + 0.3 + 0.3 * hash(1.0)) * 0.7;
		// Data rows on the left half.
		float row = floor((0.78 - uv.y) / 0.075);
		if (row >= 0.0 && row < 8.0 && uv.x > 0.06 && uv.x < 0.5) {
			float len = 0.12 + 0.32 * hash(row);
			float ry = fract((0.78 - uv.y) / 0.075);
			data += step(ry, 0.45) * step(uv.x, 0.06 + len) * 0.55;
		}
		// Trace graph on the right half.
		if (uv.x > 0.55 && uv.x < 0.94 && uv.y > 0.12 && uv.y < 0.7) {
			float gx = (uv.x - 0.55) / 0.39;
			float g = 0.4 + 0.25 * sin(gx * 9.0 + seed + t * 0.6) + 0.12 * sin(gx * 23.0 + seed * 3.0);
			float gy = (uv.y - 0.12) / 0.58;
			data += smoothstep(0.05, 0.0, abs(gy - g)) * 0.9;
			data += step(gy, g) * 0.12;
			data += step(fract(gx * 6.0), 0.03) * 0.15;
		}
		// Scan band.
		data += smoothstep(0.06, 0.0, abs(fract(uv.y - t * 0.15) - 0.5)) * 0.25;
	} else {
		// Error: a blinking warning triangle and a dead trace.
		vec2 c = (uv - vec2(0.5, 0.52)) * vec2(aspect.x, 1.0) / aspect.y;
		float tri = step(c.y, 0.22) * step(-0.18, c.y) * step(abs(c.x) * 1.15, 0.22 - c.y);
		float blink = mix(1.0, step(0.5, fract(t * 0.8)), motion);
		data += tri * 0.8 * blink;
		data += step(abs(uv.y - 0.2), 0.008) * step(0.1, uv.x) * step(uv.x, 0.9) * 0.6;
		fill = 0.05 + 0.04 * hash(floor(t * 12.0));
	}
	float scan = 0.85 + 0.15 * sin(uv.y * 220.0);
	float a = clamp(frame + corner * 0.8 + fill + data, 0.0, 1.5) * scan;
	ALBEDO = color * energy;
	ALPHA = clamp(a, 0.0, 1.0);
}
