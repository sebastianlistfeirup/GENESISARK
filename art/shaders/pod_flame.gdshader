shader_type spatial;
// Drop pod thruster plume (D-056): additive cone, UV.y runs nozzle (0) -> tip (1).
// thrust 0..1 scales brightness and length (the mesh is scaled by the script);
// flicker from a game-time uniform, never wall time.
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;

uniform float thrust = 1.0;
uniform float clock = 0.0;
uniform vec3 core : source_color = vec3(0.85, 0.97, 1.0);
uniform vec3 outer : source_color = vec3(0.2, 0.7, 1.0);
uniform float energy = 1.6;

void fragment() {
	float v = UV.y;
	float flick = 0.85 + 0.15 * sin(clock * 61.0 + UV.x * 25.0) * sin(clock * 37.0 + v * 9.0);
	float a = pow(max(1.0 - v, 0.0), 1.6) * thrust * flick;
	ALBEDO = mix(core, outer, smoothstep(0.0, 0.5, v)) * energy;
	ALPHA = clamp(a, 0.0, 1.0);
}
