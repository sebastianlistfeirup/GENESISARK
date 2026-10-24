shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;
// Atmosphere halo around a space planet (D-046): a shell slightly larger than
// the planet, glowing just outside its silhouette like the POLYGON Sci-Fi Space
// key art, so the planet's face keeps its colours. Lit by the scene's own
// lights (sun + violet fill): brightest on the day side, a faint two-tone glow
// on the night limb.
uniform vec3 halo_color : source_color = vec3(0.55, 0.85, 1.0);
uniform float strength = 1.0;
uniform float shell = 1.075;      // shell radius / planet radius (set with the mesh)
uniform float night_glow = 0.2;   // halo left on the unlit limb
uniform float face_glow = 0.12;   // a thin haze carried over the limb onto the face

void fragment() {
	float d = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	// d at which a view ray grazes the planet itself
	float ds = sqrt(max(1.0 - 1.0 / (shell * shell), 0.0001));
	float outside = smoothstep(0.0, ds, d);                       // 0 at the shell edge, 1 at the silhouette
	float over = 1.0 - smoothstep(ds, ds * 1.7, d);               // fades quickly once over the face
	float rim = pow(outside, 1.6) * mix(1.0, face_glow, smoothstep(ds * 0.92, ds * 1.08, d)) * over;
	ALBEDO = halo_color * rim * strength;
	EMISSION = halo_color * rim * strength * night_glow;
}

void light() {
	float nl = dot(NORMAL, LIGHT);
	float wrap = clamp((nl + 0.45) / 1.45, 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * wrap * 0.9;
}
