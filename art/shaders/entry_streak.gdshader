shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
// Burning air streaming past the lander during atmospheric entry: thin quads
// stretched along the flight path, hot at the head, fading to the tail. Own art.
uniform float heat = 0.0;
uniform vec3 color : source_color = vec3(1.0, 0.55, 0.2);

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = UV.y;
	ALBEDO = color * pow(across, 3.0) * along * along * heat * 3.0;
}
