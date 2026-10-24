shader_type spatial;
// Drop pod hull (D-056): one material per class (hull / accent / frame / metal / glow).
// Procedural Synty-style base: flat palette colour, per-panel tint (COLOR.r), worn
// chamfers (COLOR.g), hazard stripes (COLOR.b), thruster soot towards the belly.
// Optional baked paint from the Meshy scan on UV2 (local only, never committed),
// mixed by the bake's confidence alpha; a missing bake (fresh clone) shows the
// procedural look (hint_default_transparent).
render_mode cull_back;

uniform vec3 albedo : source_color = vec3(0.85);
uniform float roughness_v : hint_range(0.0, 1.0) = 0.6;
uniform float metallic_v : hint_range(0.0, 1.0) = 0.0;
uniform float tint_amount : hint_range(0.0, 0.3) = 0.06;
uniform float edge_wear : hint_range(0.0, 1.0) = 0.35;
uniform vec3 stripe_color : source_color = vec3(0.12, 0.12, 0.13);
// Emissive class: colour * energy * glow (glow is animated: lights dim after delivery).
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform float glow = 1.0;
// Soot from the thrusters: 0 clean, 1 after the burn (grows during the descent).
uniform float scorch : hint_range(0.0, 1.0) = 0.0;
uniform float scorch_top = 0.55;
// Baked paint from the scan (UV2). paint = 0 shows the procedural look only.
uniform sampler2D baked_albedo : source_color, hint_default_transparent, filter_linear_mipmap;
uniform sampler2D baked_orm : hint_default_transparent, filter_linear_mipmap;
uniform float paint : hint_range(0.0, 1.0) = 1.0;

varying vec3 v_local;

void vertex() {
	v_local = VERTEX;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec3 c = albedo * (1.0 + (COLOR.r - 0.5) * 2.0 * tint_amount);
	// Hazard stripes on masked parts (feet, lid rim): 45 degree bands in metres.
	float s = step(0.5, fract((UV.x + UV.y) * 9.0));
	c = mix(c, stripe_color, COLOR.b * s);
	// Fine speckle so large flat panels don't read as plastic.
	float n = hash12(floor(UV * 160.0));
	c *= 0.97 + 0.06 * n;
	// Worn chamfers: lighter, rougher edges catch the light.
	float wear = COLOR.g * edge_wear;
	c = mix(c, c * 1.18 + vec3(0.04), wear);
	float rough = mix(roughness_v, min(1.0, roughness_v + 0.15), wear);
	float metal = metallic_v;
	// Soot towards the belly after the burn.
	float soot = scorch * (1.0 - smoothstep(0.08, scorch_top, v_local.y)) * (0.75 + 0.25 * n);
	c = mix(c, c * 0.32, clamp(soot, 0.0, 0.85));
	// Baked paint from the scan, by confidence.
	vec4 b = texture(baked_albedo, UV2);
	vec4 orm = texture(baked_orm, UV2);
	float k = b.a * paint;
	c = mix(c, b.rgb * (1.0 + (COLOR.r - 0.5) * tint_amount) * mix(1.0, 0.32, clamp(soot, 0.0, 0.85)), k);
	rough = mix(rough, orm.g, orm.a * paint * 0.6);
	ALBEDO = c;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = 0.45;
	EMISSION = emission_color * emission_energy * glow;
}
