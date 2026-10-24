shader_type spatial;
// Heat shimmer (D-043): a ribbon of faint, rising, wavering mirage streaks.
// No screen-texture refraction (works the same in Compatibility and Forward+):
// thin warm bands that ripple upward and fade with height, at the ribbon's
// ends and near the camera. UV.x = arc length (m), UV.y = 0 ground .. 1 top.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.62, 0.32, 1.0);
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float strength = 0.012;   // data value; scales the streak brightness
uniform float motion = 1.0;

void fragment() {
	float t = TIME * motion;
	float warp = texture(noise_tex, vec2(UV.x * 0.09, UV.y * 0.5 - t * 0.35)).r;
	float bands = 0.5 + 0.5 * sin((UV.y * 9.0 - t * 2.2 + warp * 6.0) * 3.14159);
	bands = pow(clamp(bands, 0.0, 1.0), 6.0);  // pow of a tiny negative is NaN (white bloom)
	float fade = pow(clamp(1.0 - UV.y, 0.0, 1.0), 1.6) * smoothstep(0.0, 0.1, UV.y) * smoothstep(1.5, 6.0, length(VERTEX));
	float a = bands * fade * (0.4 + 0.8 * warp) * clamp(strength * 18.0, 0.0, 1.0);
	ALBEDO = tint.rgb * a;
	ALPHA = 1.0;
}
