shader_type spatial;
// Colony utility rover (D-065): the whole vehicle is ONE material so each moving part
// is one draw call. The material class rides in vertex colour B (class id / 16, set by
// ProcBuilder.use(..., mask)); R = per-panel tint, G = chamfer edge (wear).
// Palette colours are sRGB (converted below). Classes: 0 hull white, 1 accent orange, 2 frame charcoal, 3 metal, 4 tyre, 5 glass,
// 6 cyan strip, 7 head lamp, 8 tail/brake lamp, 9 amber beacon, 10 crate white,
// 11 crate orange, 12 hazard stripes (charcoal/yellow).
// Lamps are driven per rover (one material per rover; no instance uniforms so the
// Compatibility/web renderer works too). Optional baked paint from the Meshy scan on
// UV2 (local only, never committed), mixed by the bake's confidence; a missing bake
// (fresh clone) shows the procedural look (hint_default_transparent).
render_mode cull_back;

uniform float head : hint_range(0.0, 3.0) = 0.25;    // head lamps + light bar (night: on)
uniform float brake : hint_range(0.0, 3.0) = 0.35;   // tail lamps (braking: bright)
uniform float beacon : hint_range(0.0, 3.0) = 0.0;   // amber beacon (unloading / turning)
uniform float strip : hint_range(0.0, 3.0) = 1.0;    // cyan running strips
uniform float dirt : hint_range(0.0, 1.0) = 0.0;     // dust on the lower body (desert worlds)
uniform vec3 dirt_color : source_color = vec3(0.6, 0.5, 0.38);
uniform sampler2D baked_albedo : source_color, hint_default_transparent, filter_linear_mipmap;
uniform sampler2D baked_orm : hint_default_transparent, filter_linear_mipmap;
uniform float paint : hint_range(0.0, 1.0) = 1.0;

varying vec3 v_local;
varying flat int v_cls;

void vertex() {
	v_local = VERTEX;
	v_cls = int(COLOR.b * 16.0 + 0.01);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	int c = v_cls;
	vec3 col = vec3(0.86, 0.86, 0.84);
	float rough = 0.55;
	float metal = 0.0;
	float wear_k = 0.35;
	float paint_k = 1.0;
	vec3 emit = vec3(0.0);
	if (c == 0) { paint_k = 0.85; }
	else if (c == 1) { col = vec3(0.95, 0.5, 0.1); rough = 0.5; paint_k = 0.6; }
	else if (c == 2) { col = vec3(0.19, 0.2, 0.22); rough = 0.55; metal = 0.15; paint_k = 0.5; }
	else if (c == 3) { col = vec3(0.62, 0.64, 0.67); rough = 0.35; metal = 0.55; paint_k = 0.3; }
	else if (c == 4) { col = vec3(0.1, 0.1, 0.11); rough = 0.92; wear_k = 0.1; }
	else if (c == 5) { col = vec3(0.07, 0.085, 0.1); rough = 0.12; metal = 0.3; wear_k = 0.0; paint_k = 0.0; }
	else if (c == 6) { col = vec3(0.12, 0.32, 0.36); rough = 0.3; wear_k = 0.0; paint_k = 0.0; emit = vec3(0.2, 0.86, 1.0) * 1.6 * strip; }
	else if (c == 7) { col = vec3(0.55, 0.62, 0.66); rough = 0.2; wear_k = 0.0; paint_k = 0.0; emit = vec3(0.82, 0.95, 1.0) * 2.4 * head; }
	else if (c == 8) { col = vec3(0.35, 0.05, 0.04); rough = 0.25; wear_k = 0.0; paint_k = 0.0; emit = vec3(1.0, 0.12, 0.06) * 2.2 * brake; }
	else if (c == 9) { col = vec3(0.5, 0.3, 0.05); rough = 0.25; wear_k = 0.0; paint_k = 0.0; emit = vec3(1.0, 0.55, 0.08) * 3.0 * beacon; }
	else if (c == 10) { col = vec3(0.82, 0.83, 0.82); rough = 0.65; paint_k = 0.4; }
	else if (c == 11) { col = vec3(0.93, 0.5, 0.12); rough = 0.6; paint_k = 0.4; }
	else if (c == 12) {
		col = vec3(0.19, 0.2, 0.22);
		rough = 0.5;
		float s = step(0.5, fract((UV.x + UV.y) * 6.0));
		col = mix(col, vec3(0.92, 0.66, 0.12), s);
	}
	col = pow(col, vec3(2.2));  // palette is authored in sRGB, shading is linear
	// Per-panel tint and a fine speckle so large flat panels do not read as plastic.
	col *= 1.0 + (COLOR.r - 0.5) * 0.12;
	float n = hash12(floor(UV * 150.0));
	col *= 0.97 + 0.06 * n;
	// Worn chamfers catch the light.
	float wear = COLOR.g * wear_k;
	col = mix(col, col * 1.18 + vec3(0.04), wear);
	rough = mix(rough, min(1.0, rough + 0.15), wear);
	// Baked paint from the scan, by confidence (painted classes only). Where the scan's
	// paint disagrees strongly in brightness with the class (its trims sat a few cm
	// elsewhere), the procedural panel wins, so the bake adds the scan's shading and
	// variation without smearing charcoal over white.
	vec4 b = texture(baked_albedo, UV2);
	vec4 orm = texture(baked_orm, UV2);
	float lum_c = dot(col, vec3(0.2126, 0.7152, 0.0722));
	float lum_b = dot(b.rgb, vec3(0.2126, 0.7152, 0.0722));
	float agree = 1.0 - smoothstep(0.12, 0.3, abs(sqrt(lum_b) - sqrt(lum_c)));
	float k = smoothstep(0.55, 0.95, b.a) * paint * paint_k * agree;
	col = mix(col, b.rgb * (1.0 + (COLOR.r - 0.5) * 0.06), k);
	rough = mix(rough, orm.g, orm.a * paint * paint_k * 0.4);
	// Road dust on the lower body and the tyres (desert worlds).
	float d = dirt * (1.0 - smoothstep(0.35, 1.05, v_local.y)) * (0.7 + 0.3 * n) * step(0.01, paint_k);
	col = mix(col, dirt_color, clamp(d, 0.0, 0.75));
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
	SPECULAR = c == 5 ? 0.7 : 0.45;
	EMISSION = emit;
}
