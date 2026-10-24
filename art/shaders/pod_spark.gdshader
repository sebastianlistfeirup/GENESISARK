shader_type spatial;
// Drop pod glow particles (D-056), additive camera-facing quads on a MultiMesh.
// mode 0: closed-form burst, position = f(t, per-instance seed) (sparks from the hatch).
// mode 1: trail, positions written by the CPU per instance (energy cell trail),
//         INSTANCE_CUSTOM.x = alpha, .y = size factor.
render_mode blend_add, unshaded, depth_draw_never, cull_disabled, shadows_disabled;

uniform int mode = 0;
uniform float t = 0.0;
uniform vec3 color : source_color = vec3(0.4, 0.95, 1.0);
uniform float energy = 2.0;
uniform float size = 0.05;
uniform float life = 0.35;
uniform float speed_min = 1.0;
uniform float speed_max = 3.0;
uniform float el_min = 0.4;
uniform float el_max = 1.4;
uniform float drag = 3.0;
uniform float gravity = 4.0;
uniform float delay_spread = 0.06;

varying float v_alpha;
varying float v_hot;

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	vec3 center = vec3(0.0);
	float sz = size;
	float a = 0.0;
	if (mode == 0) {
		float az = cd.x * TAU;
		float el = mix(el_min, el_max, cd.y);
		vec3 dir = vec3(cos(el) * cos(az), sin(el), cos(el) * sin(az));
		float sp = mix(speed_min, speed_max, cd.z);
		float tt = t - cd.w * delay_spread;
		float on = step(0.0, tt) * step(t, 4.0);
		tt = max(tt, 0.0);
		center = dir * sp * (1.0 - exp(-drag * tt)) / drag + vec3(0.0, -0.5 * gravity * tt * tt, 0.0);
		float u = tt / (life * (0.6 + 0.8 * cd.w));
		a = on * exp(-u * 2.2) * (1.0 - smoothstep(0.7, 1.0, u * 0.5));
		sz = size * (0.5 + 0.8 * cd.z) * max(0.15, 1.0 - u * 0.6);
		v_hot = exp(-u * 4.0);
	} else {
		a = cd.x;
		sz = size * cd.y;
		v_hot = cd.x;
	}
	vec3 world = (MODEL_MATRIX * vec4(center, 1.0)).xyz;
	vec4 vp = VIEW_MATRIX * vec4(world, 1.0);
	vp.xy += VERTEX.xy * sz;
	POSITION = PROJECTION_MATRIX * vp;
	v_alpha = a;
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float k = pow(max(1.0 - d, 0.0), 1.8);
	ALBEDO = mix(color, vec3(1.0), v_hot * 0.55 * k) * energy;
	ALPHA = clamp(v_alpha * k, 0.0, 1.0);
}
