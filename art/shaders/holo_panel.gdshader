shader_type canvas_item;
// Holo-console overlay for UI panels (D-055, HoloFrame): fine scanlines, a slow
// bright scan band, film grain, a soft edge glow that hugs the panel border and
// a boot reveal (the panel is "printed" top-down behind a bright line). Drawn
// OVER the panel content with ordinary alpha blending, so it never darkens text
// except below the boot line. Own procedural art, no vendor data.
// motion = 0 (reduced motion): no band, no grain flicker, no scroll.

uniform vec4 glow_color : source_color = vec4(0.36, 0.92, 0.9, 1.0);
uniform vec4 fill_color : source_color = vec4(0.03, 0.07, 0.1, 1.0);  // what hides content before boot
uniform vec2 px_size = vec2(800.0, 600.0);  // control size in px, set by HoloFrame
uniform float boot = 1.0;       // 0 -> 1: reveal progress (1 = fully shown)
uniform float motion = 1.0;
uniform float scan = 0.05;      // scanline strength
uniform float edge = 0.55;      // edge glow strength
uniform float band = 0.06;      // scan band strength
uniform float grain = 0.025;
uniform float flash = 0.0;      // 0..1 brief white-cyan flash (boot)

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 px = UV * px_size;
	float t = TIME * motion;
	// Distance to the nearest edge in px.
	vec2 e2 = min(px, px_size - px);
	float d = min(e2.x, e2.y);
	float glow = exp(-d / 10.0) * 0.75 + exp(-d / 46.0) * 0.25;
	// Corners burn a little brighter.
	float corner = exp(-length(e2) / 60.0);
	float a = (glow + corner * 0.6) * edge;
	// Scanlines (3 px period), drifting slowly downwards.
	float sl = 0.5 + 0.5 * sin((px.y + t * 18.0) * 2.0944);
	a += sl * scan;
	// The scan band: a soft bright stripe crossing every ~7 s.
	float by = fract(t * 0.14) * (px_size.y + 400.0) - 200.0;
	a += exp(-pow((px.y - by) / 60.0, 2.0)) * band;
	// Grain.
	a += (hash(floor(px * 0.5) + floor(t * 24.0)) - 0.5) * grain * motion;
	vec4 col = vec4(glow_color.rgb, clamp(a, 0.0, 0.85) * glow_color.a);
	// Boot flash over the printed part only (the unprinted plate stays dark).
	col.rgb = mix(col.rgb, vec3(0.8, 1.0, 1.0), flash);
	col.a = max(col.a, flash * 0.5);
	// Boot: below the reveal line the content is still hidden behind the fill;
	// the line itself is a bright cyan stroke with a falling glow.
	float line_y = boot * (px_size.y + 24.0) - 12.0;
	if (boot < 1.0) {
		float below = smoothstep(line_y - 2.0, line_y + 2.0, px.y);
		// Not yet printed: the dark plate with a faint blueprint grid.
		vec2 cell = abs(fract(px / 24.0) - 0.5);
		float gridl = smoothstep(0.47, 0.5, max(cell.x, cell.y));
		vec3 plate = fill_color.rgb + glow_color.rgb * gridl * 0.08;
		col = mix(col, vec4(plate, 1.0), below);
		float stroke = exp(-abs(px.y - line_y) / 3.0) + exp(-max(0.0, line_y - px.y) / 40.0) * 0.35 * (1.0 - below);
		col.rgb = mix(col.rgb, vec3(0.75, 1.0, 1.0), clamp(stroke, 0.0, 1.0));
		col.a = max(col.a, clamp(stroke, 0.0, 1.0));
	}
	COLOR = col;
}
