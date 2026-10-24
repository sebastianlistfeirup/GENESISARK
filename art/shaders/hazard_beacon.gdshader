shader_type spatial;
// Hazard beacon lamp (D-043): a light chases around the zone edge, each lamp
// flaring as the chase passes its bearing from the zone centre. With reduced
// motion (motion = 0) every lamp glows steadily.
render_mode unshaded, shadows_disabled;

uniform vec4 lamp_color : source_color = vec4(1.0, 0.7, 0.2, 1.0);
uniform vec3 center = vec3(0.0);
uniform float motion = 1.0;
uniform float glow = 2.2;

void fragment() {
	vec3 p = NODE_POSITION_WORLD;
	float ang = atan(p.z - center.z, p.x - center.x) / 6.2831853;
	float ph = fract(ang + TIME * 0.32);
	float pulse = pow(clamp(ph, 0.0, 1.0), 10.0);
	float k = mix(0.75, 0.45 + 1.6 * pulse, step(0.5, motion));
	ALBEDO = lamp_color.rgb * glow * k;
}
