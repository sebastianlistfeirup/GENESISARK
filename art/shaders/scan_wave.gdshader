shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
// Scanner wavefront: an open cylinder that grows across the terrain; bright at the
// ground, fading upward, with fine vertical scan lines. `fade` 1 -> 0 over its life. Own art.
uniform vec3 color : source_color = vec3(0.35, 1.0, 0.95);
uniform float fade = 1.0;

void fragment() {
	float up = clamp(UV.y, 0.0, 1.0);          // 0 top, 1 bottom on Godot's CylinderMesh
	float body = pow(up, 2.2) + 0.12;
	float lines = 0.65 + 0.35 * step(0.5, fract(UV.x * 160.0));
	ALBEDO = color * body * lines * fade * 2.6;
}
