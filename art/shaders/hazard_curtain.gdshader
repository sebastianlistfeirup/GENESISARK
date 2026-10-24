shader_type spatial;
// Hazard zone edge curtain (D-043): a low ribbon of haze standing on the zone
// edge, fading to nothing at the top, broken into drifting wisps by scrolling
// noise. UV.x = arc length (m), UV.y = 0 at the ground .. 1 at the top.
// Fades out near the camera so walking through it never fills the screen.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec4 zone_color : source_color = vec4(0.84, 0.77, 0.28, 1.0);
uniform float strength = 0.32;
uniform float motion = 1.0;
uniform float brightness = 1.15;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;

void fragment() {
	float v = UV.y;
	float t = TIME * motion;
	float n = texture(noise_tex, vec2(UV.x * 0.05 + t * 0.012, v * 0.3 - t * 0.05)).r;
	float n2 = texture(noise_tex, vec2(UV.x * 0.13 - t * 0.02, v * 0.7 - t * 0.12)).r;
	float fade = pow(clamp(1.0 - v, 0.0, 1.0), 2.0) * smoothstep(0.0, 0.06, v);
	float a = strength * fade * (0.3 + 1.2 * n * n2);
	a *= smoothstep(1.5, 6.0, length(VERTEX));
	ALBEDO = zone_color.rgb * brightness;
	ALPHA = clamp(a, 0.0, 1.0);
}
