shader_type spatial;
// Alien skin for the ground wildlife (GroundWildlife, D-053). The purchased
// creatures are flat-colour UV atlases, so a world can recolour them freely:
//  - hue/saturation/value shift of the original paint, then a two-tone
//    gradient map (dark -> light) mixed in by grad_amount: same animal, alien hide;
//  - glow: the pack's own emission map, the brightest texels (antlers, horns,
//    bellies: glow_min), and/or bioluminescent dorsal bands in mesh space.
// Own art.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D emit_tex : source_color, hint_default_black, filter_linear_mipmap;
uniform float hue_shift = 0.0;
uniform float sat = 1.0;
uniform float val = 1.0;
uniform vec3 grad_dark : source_color = vec3(0.1);
uniform vec3 grad_light : source_color = vec3(0.9);
uniform float grad_amount = 0.0;
uniform float roughness = 0.85;
uniform vec3 emit_color : source_color = vec3(1.0);
uniform float emit_energy = 0.0;      // pack emission map
uniform vec3 glow_color : source_color = vec3(0.3, 1.0, 0.9);
uniform float glow_energy = 0.0;      // brightest texels
uniform float glow_min = 0.72;        // value threshold for texel glow
uniform float band_energy = 0.0;      // dorsal bands
uniform float band_freq = 6.0;        // bands per metre along the body
uniform vec3 up_axis = vec3(0.0, 0.0, 1.0);    // mesh-space up / length axes (set per model)
uniform vec3 long_axis = vec3(0.0, 1.0, 0.0);
uniform float body_height = 1.0;      // mesh units: bands only on the upper body
uniform float phase = 0.0;
uniform float pulse_speed = 1.3;   // 0 with reduced motion

varying vec3 mpos;
varying vec3 mnrm;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void vertex() {
	mpos = VERTEX;
	mnrm = NORMAL;
}

void fragment() {
	vec3 src = texture(albedo_tex, UV).rgb;
	vec3 hsv = rgb2hsv(src);
	float lum = hsv.z;
	hsv.x = fract(hsv.x + hue_shift);
	hsv.y = clamp(hsv.y * sat, 0.0, 1.0);
	hsv.z = clamp(hsv.z * val, 0.0, 1.0);
	vec3 c = hsv2rgb(hsv);
	vec3 g = mix(grad_dark, grad_light, smoothstep(0.1, 0.62, lum));
	c = mix(c, g, grad_amount);
	ALBEDO = c;
	ROUGHNESS = roughness;
	vec3 em = texture(emit_tex, UV).rgb * emit_color * emit_energy;
	em += glow_color * glow_energy * smoothstep(glow_min, glow_min + 0.12, lum);
	if (band_energy > 0.0) {
		float h = dot(mpos, up_axis) / max(body_height, 0.001);
		float top = smoothstep(0.45, 0.7, h) * smoothstep(0.1, 0.5, dot(normalize(mnrm), up_axis));
		float l = dot(mpos, long_axis) * band_freq + phase;
		float band = smoothstep(0.55, 0.85, sin(l * 6.2831853) * 0.5 + 0.5);
		float pulse = 0.75 + 0.25 * sin(TIME * pulse_speed + phase * 3.0);
		em += glow_color * band_energy * band * top * pulse;
	}
	EMISSION = em;
}
