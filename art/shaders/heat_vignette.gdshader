shader_type canvas_item;
// Screen-edge glow while the lander burns through the upper atmosphere. Own art.
uniform float heat = 0.0;
uniform vec4 tint : source_color = vec4(1.0, 0.45, 0.12, 1.0);

void fragment() {
	vec2 d = UV * 2.0 - 1.0;
	float edge = smoothstep(0.55, 1.35, length(d * vec2(1.0, 1.25)));
	float flick = 0.85 + 0.15 * sin(TIME * 23.0 + d.x * 7.0);
	COLOR = vec4(tint.rgb, edge * heat * 0.55 * flick);
}
