shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled, unshaded, fog_disabled;
// Sky variant of cloud_puff (no depth fog; it fades by distance itself): the cloud deck over a surface. Based on: camera-facing cloud puffs for the descent: soft lumpy discs lit
// on the sun side, fading out when the camera flies through them (no hard
// planes slicing the view) and with distance into the sky. Own art.
uniform vec3 lit : source_color = vec3(1.0, 0.97, 0.92);
uniform vec3 shade : source_color = vec3(0.62, 0.66, 0.78);
uniform float opacity = 0.85;
uniform float near_fade = 90.0;
uniform float far_fade = 9000.0;
uniform float presence = 1.0;  // the descent fades the deck in on the way down

varying float cam_dist;
varying float seed;

// Sine-free hash (the fract(sin()) one showed square blocks inside the puffs).
float h(vec2 p) { vec3 q = fract(vec3(p.xyx) * 0.1031); q += dot(q, q.yzx + 33.33); return fract((q.x + q.y) * q.z); }
float n2(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	// Billboard: keep the instance's scale, face the camera.
	vec3 centre = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float s = length(MODEL_MATRIX[0].xyz);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = centre + (right * VERTEX.x + up * VERTEX.y * 0.55) * s;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
	cam_dist = length(world - CAMERA_POSITION_WORLD);
	seed = fract(centre.x * 0.013 + centre.z * 0.007);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float r = length(uv);
	float lump = n2(uv * 2.6 + seed * 40.0) * 0.35 + n2(uv * 6.0 + seed * 17.0) * 0.15;
	float a = smoothstep(1.0, 0.35, r + lump * 0.6 - 0.2);
	a *= smoothstep(near_fade * 0.3, near_fade, cam_dist) * (1.0 - smoothstep(far_fade * 0.6, far_fade, cam_dist));
	float top = clamp(0.5 - uv.y * 0.5 + lump, 0.0, 1.0);
	ALBEDO = mix(shade, lit, top);
	ALPHA = a * opacity * presence;
}
