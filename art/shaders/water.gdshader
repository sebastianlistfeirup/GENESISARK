shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;
// Stylised sea for wet worlds: depth-tinted (shallow turquoise -> deep blue),
// animated faceted ripples, fresnel sky reflection and soft foam at the shore.
// Own art (no vendor data).
uniform vec3 shallow : source_color = vec3(0.2, 0.75, 0.72);
uniform vec3 deep : source_color = vec3(0.03, 0.2, 0.36);
uniform vec3 foam_color : source_color = vec3(0.95, 0.98, 1.0);
uniform float depth_fade = 3.5;
uniform float foam_width = 0.9;
uniform float wave_speed = 0.35;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear_mipmap;

float h2(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float n2(vec2 x) { vec2 i = floor(x); vec2 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y); }

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += (n2(wpos.xz * 0.15 + TIME * wave_speed) - 0.5) * 0.25;
}

void fragment() {
	float t = TIME * wave_speed;
	float a = n2(wpos.xz * 0.6 + vec2(t, t * 0.7));
	float b = n2(wpos.xz * 1.3 - vec2(t * 0.8, t));
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4((a - 0.5) * 0.35, 0.0, (b - 0.5) * 0.35, 0.0)).xyz);
	float scene_depth = texture(depth_tex, SCREEN_UV).r;
	vec4 world = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	world.xyz /= world.w;
	float water_depth = clamp((-world.z) - (-VERTEX.z), 0.0, 100.0);
	float k = clamp(water_depth / depth_fade, 0.0, 1.0);
	vec3 col = mix(shallow, deep, k);
	float foam = (1.0 - smoothstep(0.0, foam_width, water_depth)) * smoothstep(0.35, 0.65, n2(wpos.xz * 2.2 + t * 2.0));
	col = mix(col, foam_color, foam * 0.85);
	ALBEDO = col;
	ALPHA = clamp(0.55 + k * 0.4 + foam, 0.0, 0.95);
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.7;
}
