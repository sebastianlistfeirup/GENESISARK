shader_type spatial;
// Drop pod dust and steam (D-056): closed-form soft puffs on a MultiMesh, every
// puff's position a pure function of t and its seed (INSTANCE_CUSTOM: azimuth,
// speed, size, phase). loop_rate > 0 cycles them (thruster wash, hiss); 0 = one
// shot from t = 0 (impact ring). Lit by the scene (camera-facing normal), so dust
// is dark on a night planet and bright in a desert noon; `light` scales it.
render_mode blend_mix, skip_vertex_transform, depth_draw_never, cull_disabled, shadows_disabled;

uniform float t = 0.0;
uniform float loop_rate = 0.0;
uniform float life = 1.6;
uniform float delay = 0.05;
uniform float r0 = 0.5;
uniform float radial_speed = 3.0;
uniform float drag = 2.5;
uniform float rise = 0.25;
uniform float height0 = 0.05;
uniform float size0 = 0.25;
uniform float size1 = 0.9;
uniform vec3 color : source_color = vec3(0.6, 0.55, 0.45);
uniform float light = 1.0;
uniform float opacity = 0.55;
uniform float strength = 1.0;

varying float v_alpha;
varying float v_seed;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1, 0)), f.x), mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	vec4 cd = INSTANCE_CUSTOM;
	float u;
	float tt;
	float on = 1.0;
	if (loop_rate > 0.0) {
		u = fract(t * loop_rate + cd.w);
		tt = u * life;
	} else {
		tt = t - cd.w * delay;
		on = step(0.0, tt);
		tt = max(tt, 0.0);
		u = tt / life;
	}
	float az = cd.x * TAU;
	float sp = 0.55 + 0.9 * cd.y;
	float r = r0 + radial_speed * sp * (1.0 - exp(-drag * tt)) / drag;
	vec3 center = vec3(cos(az) * r, height0 + rise * tt * (0.6 + 0.8 * cd.z), sin(az) * r);
	float sz = mix(size0, size1, sqrt(clamp(u, 0.0, 1.0))) * (0.6 + 0.8 * cd.z);
	v_alpha = on * opacity * strength * smoothstep(0.0, 0.08, u) * pow(max(1.0 - u, 0.0), 1.5);
	v_seed = cd.w * 17.0 + cd.x * 5.0;
	float ang = az + tt * (cd.y - 0.5) * 1.5;
	vec2 q = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang))) * VERTEX.xy;
	vec3 world = (MODEL_MATRIX * vec4(center, 1.0)).xyz;
	vec4 vp = VIEW_MATRIX * vec4(world, 1.0);
	vp.xy += q * sz;
	VERTEX = vp.xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 p = UV - 0.5;
	float d = length(p) * 2.0;
	float n = vnoise(UV * 3.5 + v_seed) * 0.6 + vnoise(UV * 7.0 - v_seed) * 0.4;
	float a = smoothstep(1.0, 0.25, d + (n - 0.5) * 0.55);
	ALBEDO = color * light * (0.85 + 0.25 * n);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	BACKLIGHT = vec3(0.35);
	ALPHA = clamp(v_alpha * a, 0.0, 1.0);
}
