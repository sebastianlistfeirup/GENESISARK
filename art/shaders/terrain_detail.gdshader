shader_type spatial;
// Faceted terrain with ground detail: the vertex colour stays the planet's tone;
// a world-space ground texture (grass, sand, snow...) and a cliff texture on
// steep faces add the close-up detail of the Nature Biomes terrain, as luminance
// only, so every planet keeps its own colour. Far away the detail fades out.
uniform sampler2D ground_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D cliff_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float ground_scale = 0.35;
uniform float cliff_scale = 0.12;
uniform float strength = 1.0;
uniform float fade_distance = 70.0;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

float lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

void fragment() {
	vec3 base = COLOR.rgb;
	float g = lum(texture(ground_tex, wpos.xz * ground_scale).rgb);
	vec3 w = pow(abs(wnrm), vec3(4.0));
	w /= (w.x + w.y + w.z);
	float c = lum(texture(cliff_tex, wpos.zy * cliff_scale).rgb) * w.x + lum(texture(cliff_tex, wpos.xy * cliff_scale).rgb) * w.z + g * w.y;
	float steep = smoothstep(0.75, 0.55, wnrm.y);
	float detail = mix(g, c, steep);
	float fade = 1.0 - smoothstep(fade_distance * 0.5, fade_distance, length(VERTEX));
	ALBEDO = base * mix(1.0, 0.35 + detail * 1.35, strength * fade);
	ROUGHNESS = 0.95;
}
