shader_type spatial;
render_mode cull_disabled;
// Life for rigid creature meshes (Meshy, no skeleton): "wing" mode flaps the
// body's sides around its long axis (mantas, sky whales: tail sways too);
// "pulse" mode contracts the bell and waves the tentacles (jellyfish).
// Bioluminescent glow optional. Own art.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(1.0);
uniform int mode = 0;              // 0 wing, 1 pulse
uniform float amount = 0.25;
uniform float speed = 1.0;
uniform float half_span = 1.0;     // half width (wing) or height (pulse) in mesh units
uniform float phase = 0.0;
uniform vec3 glow_color : source_color = vec3(0.3, 1.0, 0.9);
uniform float glow = 0.0;
uniform float alpha = 1.0;

varying float edge;

void vertex() {
	float t = TIME * speed + phase;
	if (mode == 0) {
		float side = clamp(abs(VERTEX.x) / half_span, 0.0, 1.0);
		edge = side;
		VERTEX.y += sin(t) * amount * half_span * side * side;
		VERTEX.x += sin(VERTEX.z * 0.8 + t) * amount * 0.15 * half_span * smoothstep(0.0, 1.0, -VERTEX.z / max(half_span, 0.01));
	} else {
		float down = clamp(-VERTEX.y / half_span, 0.0, 1.0);
		edge = down;
		float squeeze = 1.0 - amount * 0.5 * (0.5 + 0.5 * sin(t)) * (1.0 - down);
		VERTEX.xz *= squeeze;
		VERTEX.xz += vec2(sin(t * 1.3 + VERTEX.y * 3.0), cos(t + VERTEX.y * 2.5)) * amount * 0.25 * half_span * down;
	}
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb * tint;
	ALBEDO = c;
	ROUGHNESS = 0.6;
	EMISSION = glow_color * glow * (0.4 + 0.6 * edge);
	if (alpha < 0.999) {
		ALPHA = alpha;
	}
}
