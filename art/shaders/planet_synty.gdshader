shader_type spatial;
render_mode fog_disabled;
// Planets after the POLYGON Sci-Fi Space planet sheet (D-044): the pack's own
// planet masks (land, clouds, banded lines; local, gitignored) painted in soft
// pastel colours on a faceted sphere: banded gas giants, terran worlds with
// continents and clouds, cratered moons, glowing crystal/lava veins. The masks
// are projected in object space (latitude/longitude for the bands, triplanar
// for land and clouds), so any sphere-like mesh works. Fallback without the
// pack: PlanetLook keeps art/shaders/planet.gdshader.
uniform sampler2D land_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D cloud_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D lines_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec3 ocean_color : source_color = vec3(0.12, 0.35, 0.62);
uniform vec3 land_color : source_color = vec3(0.45, 0.78, 0.32);
uniform vec3 land_color2 : source_color = vec3(0.85, 0.9, 0.45);
uniform vec3 band_a : source_color = vec3(0.95, 0.75, 0.55);
uniform vec3 band_b : source_color = vec3(0.85, 0.45, 0.35);
uniform vec3 cloud_color : source_color = vec3(1.0);
uniform vec3 atmo_color : source_color = vec3(0.6, 0.8, 1.0);
uniform vec3 vein_color : source_color = vec3(0.7, 0.35, 1.0);
uniform float land_amount = 1.0;   // 0 = no continents (gas giant / moon)
uniform float land_scale = 1.0;
uniform float sea_shift = 0.0;     // >0 = more ocean
uniform float bands = 0.0;         // weight of the banded lines texture
uniform float band_scale = 1.0;    // number of band repeats pole to pole
uniform float band_wobble = 0.04;
uniform float cloud_amount = 0.0;
uniform float craters = 0.0;       // procedural crater bowls and rims (rocky moons)
uniform float crater_scale = 5.0;
uniform float vein_amount = 0.0;   // glowing cracks along the land-mask edges
uniform float vein_energy = 3.0;
uniform float rim_energy = 1.2;
uniform float soft_light = 0.55;   // wrap lighting: pastel key-art look
uniform float seed = 0.0;
uniform float spin_speed = 0.0;    // clouds/bands drift (0 with reduced motion)
uniform float city_lights = 0.0;
uniform vec3 sun_dir = vec3(0.6, 0.3, 0.75);
uniform vec3 settlement = vec3(0.3, 0.35, 0.88);

varying vec3 obj_n;
varying vec3 obj_p;

void vertex() {
	obj_p = VERTEX;
	obj_n = normalize(VERTEX);
}

float hash(vec3 p3) { p3 = fract((p3 + seed * 0.731) * 0.1031); p3 += dot(p3, p3.zyx + 31.32); return fract((p3.x + p3.y) * p3.z); }

// Nearest crater around p: x = distance to its centre / its radius, y = present.
vec2 crater(vec3 p) {
	vec3 c = floor(p);
	float best = 9.0;
	float on = 0.0;
	for (int x = -1; x <= 1; x++) for (int y = -1; y <= 1; y++) for (int z = -1; z <= 1; z++) {
		vec3 cell = c + vec3(float(x), float(y), float(z));
		float h = hash(cell + 5.3);
		vec3 centre = cell + vec3(hash(cell + 1.1), hash(cell + 2.2), hash(cell + 3.3));
		float rr = 0.25 + 0.4 * hash(cell + 7.7);
		float d = length(p - centre) / rr;
		if (d < best && h < 0.55) { best = d; on = 1.0; }
	}
	return vec2(best, on);
}

vec3 tri_w(vec3 n) { vec3 w = pow(abs(n), vec3(4.0)); return w / (w.x + w.y + w.z); }

float tri(sampler2D t, vec3 n, float s, vec2 off, float lod_bias) {
	vec3 w = tri_w(n);
	vec3 p = n * s;
	float a = texture(t, p.zy * 0.5 + off, lod_bias).r;
	float b = texture(t, p.xz * 0.5 + off + vec2(0.37, 0.11), lod_bias).r;
	float c = texture(t, p.xy * 0.5 + off + vec2(0.71, 0.53), lod_bias).r;
	return a * w.x + b * w.y + c * w.z;
}

void fragment() {
	vec3 n = obj_n;
	float spin = TIME * spin_speed;
	float lon = atan(n.z, n.x) / 6.2831853 + 0.5;
	float lat = asin(clamp(n.y, -1.0, 1.0)) / 3.14159265 + 0.5;
	vec2 off = vec2(fract(seed * 0.137), fract(seed * 0.291));
	// Bands: the pack's line texture, read along latitude with a little wobble.
	float wob = (texture(cloud_tex, vec2(lon * 2.0 + off.x, lat * 1.5 + off.y)).r - 0.5) * band_wobble;
	float line = texture(lines_tex, vec2(lon + spin * 0.5 + off.x, lat * band_scale + wob + off.y)).r;
	float line2 = texture(lines_tex, vec2(lon * 2.0 + 0.3, lat * band_scale * 0.5 + 0.21 + wob)).r;
	vec3 band_col = mix(band_a, band_b, line);
	band_col = mix(band_col, band_col * 1.12 + 0.04, line2 * 0.35);
	// Continents: the land mask, softened a touch so coasts read as painted.
	float land_raw = tri(land_tex, n, land_scale, off, 2.5);
	float land = smoothstep(0.42 + sea_shift, 0.58 + sea_shift, land_raw) * land_amount;
	float inland = smoothstep(0.6 + sea_shift, 0.98, tri(land_tex, n, land_scale, off, 4.0));
	vec3 terr = mix(land_color, land_color2, inland * 0.8 + 0.2 * line2);
	vec3 col = mix(band_col, ocean_color, land_amount * (1.0 - land));
	col = mix(col, terr, land);
	col = mix(col, band_col, bands * 0.55 * land_amount);  // banded tint over terran worlds too
	// Clouds: the cloud mask, drifting.
	vec3 cn = n;
	float a = spin;
	cn.xz = mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a))) * cn.xz;
	if (craters > 0.0) {
		vec2 cr = crater(n * crater_scale + seed);
		vec2 cr2 = crater(n * crater_scale * 2.3 + seed + 11.0);
		float bowl = (1.0 - smoothstep(0.55, 0.95, cr.x)) * cr.y + (1.0 - smoothstep(0.55, 0.95, cr2.x)) * cr2.y * 0.6;
		float rim_l = smoothstep(0.8, 0.98, cr.x) * (1.0 - smoothstep(0.98, 1.2, cr.x)) * cr.y;
		col *= 1.0 - bowl * 0.38 * craters;
		col += rim_l * 0.07 * craters;
	}
	float cl = smoothstep(0.42, 0.75, tri(cloud_tex, cn, 1.3, off.yx, 0.0)) * cloud_amount;
	col = mix(col, cloud_color, cl * 0.85);
	ALBEDO = col;
	ROUGHNESS = 0.85;
	SPECULAR = 0.25;
	// Pastel wrap light + atmosphere rim (the sheet's soft glow).
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	EMISSION = atmo_color * rim * rim_energy + col * soft_light * 0.1;
	if (vein_amount > 0.0) {
		float e1 = abs(tri(land_tex, n, land_scale * 1.2, off, 3.5) - 0.5);
		float e2 = abs(tri(land_tex, n.zxy, land_scale * 2.4, off.yx, 3.0) - 0.5);
		float edge = 1.0 - smoothstep(0.02, 0.09, e1);
		float edge2 = 1.0 - smoothstep(0.01, 0.06, e2);
		float glow = edge + edge2 * 0.45;
		ALBEDO = mix(ALBEDO, vein_color, clamp(glow, 0.0, 1.0) * vein_amount * 0.6);
		EMISSION += vein_color * glow * vein_amount * vein_energy;
	}
	if (city_lights > 0.0) {
		float night = smoothstep(0.05, -0.25, dot(n, normalize(sun_dir)));
		float near = smoothstep(0.86, 0.985, dot(n, normalize(settlement)));
		float dots = step(0.82, hash(floor(n * 160.0))) * max(land, 1.0 - land_amount);
		EMISSION += vec3(1.0, 0.72, 0.35) * dots * near * night * city_lights * 3.0;
	}
}

void light() {
	float nl = dot(NORMAL, LIGHT);
	float wrap = clamp((nl + soft_light) / (1.0 + soft_light), 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * wrap / 3.14159265;
}
