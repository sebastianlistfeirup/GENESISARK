shader_type spatial;
// Synty atlas with "light strips": saturated bright texels (the cyan/amber
// light bars painted into the atlas) also emit, so glow/bloom picks them up as
// in the pack's key art. Everything else shades like a plain atlas material.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float roughness = 0.62;
uniform float metallic = 0.25;
uniform float glow_energy = 2.4;
uniform float sat_min = 0.55;
uniform float val_min = 0.75;
uniform vec3 glow_tint : source_color = vec3(1.0);  // ship on emergency power: strips shift to this colour
uniform float tint_amount = 0.0;
uniform vec3 albedo_mul : source_color = vec3(1.0);  // per-use grade (the flight cockpit's mauve)
// Atlas regions that are painted, not lit (yellow/black hazard stripes): never
// emit, so floors and doors do not read as neon. Rects are (u0, v0, u1, v1).
uniform vec4 no_glow_a = vec4(0.0);
uniform vec4 no_glow_b = vec4(0.0);
// Lit window strips (D-044, the capital ships of the key art): rows of small
// warm windows on side-facing faces, in mesh units. 0 = off (every other user).
uniform float window_amount = 0.0;
uniform vec2 window_cell = vec2(3.2, 3.6);   // spacing along z, y
uniform vec2 window_size = vec2(0.55, 0.32); // lit fraction of a cell
uniform vec3 window_color : source_color = vec3(1.0, 0.82, 0.55);
uniform vec3 window_color2 : source_color = vec3(0.45, 0.95, 1.0);
uniform float window_energy = 3.0;

varying vec3 obj_pos;
varying vec3 obj_nrm;

void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
}

float whash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float in_rect(vec2 uv, vec4 r) {
	return step(r.x, uv.x) * step(uv.x, r.z) * step(r.y, uv.y) * step(uv.y, r.w);
}

void fragment() {
	vec3 raw = texture(albedo_tex, UV).rgb;
	vec3 c = raw;
	ALBEDO = c;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	float mx = max(c.r, max(c.g, c.b));
	float mn = min(c.r, min(c.g, c.b));
	float sat = mx > 0.0 ? (mx - mn) / mx : 0.0;
	float mask = smoothstep(sat_min, sat_min + 0.15, sat) * smoothstep(val_min, val_min + 0.15, mx);
	mask *= 1.0 - max(in_rect(UV, no_glow_a), in_rect(UV, no_glow_b));
	vec3 strip = mix(c, glow_tint * mx, tint_amount);
	EMISSION = strip * mask * glow_energy;
	ALBEDO = mix(c * albedo_mul, strip, mask);
	if (window_amount > 0.0) {
		// side faces only, on plain hull plating (not on lit strips or dark vents)
		float side = smoothstep(0.75, 0.9, abs(normalize(obj_nrm).x));
		vec2 q = vec2(obj_pos.z, obj_pos.y) / window_cell;
		vec2 cell = floor(q);
		vec2 f = fract(q);
		float lit = step(0.35, whash(cell + sign(obj_pos.x) * 17.0));
		float rect = step(abs(f.x - 0.5), window_size.x * 0.5) * step(abs(f.y - 0.5), window_size.y * 0.5);
		float plate = (1.0 - mask) * smoothstep(0.12, 0.3, mx);
		float win = side * rect * lit * plate * window_amount;
		vec3 wc = mix(window_color, window_color2, step(0.82, whash(cell * 1.7 + 3.0)));
		ALBEDO = mix(ALBEDO, wc, win);
		EMISSION += wc * win * window_energy;
	}
}
