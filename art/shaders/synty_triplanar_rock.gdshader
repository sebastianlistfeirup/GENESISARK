shader_type spatial;
// Rocks and cliffs of the Nature Biomes packs are triplanar in Unity (their UVs
// all sit on one texel). World-space triplanar here: side texture on walls,
// top texture (moss/sand/snow) on upward faces, tinted per planet.
uniform sampler2D side_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D top_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 side_tint : source_color = vec3(1.0);
uniform vec3 top_tint : source_color = vec3(1.0);
uniform float scale = 0.18;
uniform float top_amount = 0.55;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 w = pow(abs(wnrm), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 sx = texture(side_tex, wpos.zy * scale).rgb;
	vec3 sz = texture(side_tex, wpos.xy * scale).rgb;
	vec3 ty = texture(top_tex, wpos.xz * scale).rgb;
	vec3 side = (sx * w.x + sz * w.z + texture(side_tex, wpos.xz * scale).rgb * w.y) * side_tint;
	float up = smoothstep(top_amount, top_amount + 0.2, wnrm.y);
	ALBEDO = mix(side, ty * top_tint, up);
	ROUGHNESS = 0.92;
}
