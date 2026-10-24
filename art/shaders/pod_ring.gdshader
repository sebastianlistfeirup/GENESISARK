shader_type spatial;
// Drop pod rings (D-056), additive, on a flat 1x1 plane (UV centred at 0.5):
// the landing target marker (dashed, slowly turning), the hatch burst ring and
// the suit absorb ring. radius/width in UV units of the plane, alpha animated.
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 color : source_color = vec3(0.35, 0.9, 1.0);
uniform float energy = 1.5;
uniform float alpha = 1.0;
uniform float radius = 0.4;
uniform float width = 0.04;
uniform float dashes = 0.0;
uniform float spin = 0.0;
uniform float inner_fill = 0.0;

void fragment() {
	vec2 p = UV - 0.5;
	float d = length(p);
	float ring = smoothstep(width, 0.0, abs(d - radius));
	if (dashes > 0.0) {
		float a = atan(p.y, p.x) / TAU + spin;
		ring *= smoothstep(0.15, 0.3, abs(fract(a * dashes) - 0.5) * 2.0);
	}
	float fill = inner_fill * smoothstep(radius, 0.0, d) * 0.25;
	ALBEDO = color * energy;
	ALPHA = clamp((ring + fill) * alpha * smoothstep(0.5, 0.45, d), 0.0, 1.0);
}
