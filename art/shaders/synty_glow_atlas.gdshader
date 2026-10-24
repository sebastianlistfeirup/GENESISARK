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
// Atlas regions that are painted, not lit (yellow/black hazard stripes): never
// emit, so floors and doors do not read as neon. Rects are (u0, v0, u1, v1).
uniform vec4 no_glow_a = vec4(0.0);
uniform vec4 no_glow_b = vec4(0.0);

float in_rect(vec2 uv, vec4 r) {
	return step(r.x, uv.x) * step(uv.x, r.z) * step(r.y, uv.y) * step(uv.y, r.w);
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
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
	ALBEDO = mix(c, strip, mask);
}
