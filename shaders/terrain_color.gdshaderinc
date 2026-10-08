// Ground colour as a function of world position only: everything the terrain shader does that does not
// depend on the camera. It is baked once into textures at load (see scripts/world/terrain_bake.gd), because
// evaluating it per pixel (about ten noise lookups, several octaves and a dozen region masks) was the
// largest fragment cost on phones, where the ground covers about half the screen.
// Needs common.gdshaderinc (h2, n2, fbm2) to be included first.
uniform vec3 grass_a : source_color = vec3(0.34, 0.43, 0.23);
uniform vec3 grass_b : source_color = vec3(0.25, 0.35, 0.16);
uniform vec3 grass_dry : source_color = vec3(0.49, 0.47, 0.30);
uniform vec3 dirt : source_color = vec3(0.40, 0.33, 0.22);
uniform vec3 gravel : source_color = vec3(0.52, 0.50, 0.46);
uniform vec3 forest : source_color = vec3(0.10, 0.17, 0.07);
uniform vec4 field_rect = vec4(-200.0, -110.0, 200.0, 110.0);
uniform vec4 grass_rwy = vec4(-80.0, -30.0, 80.0, -14.0);
uniform vec4 gravel_rect = vec4(-52.0, 44.0, 32.0, 72.0);
uniform vec4 pits_rect = vec4(-47.0, 19.0, 32.0, 41.0);

// In a spatial shader source_color uniforms arrive as linear; in the canvas bake shader they stay sRGB.
#ifdef TERRAIN_BAKE
vec3 U(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
#else
vec3 U(vec3 c) {
	return c;
}
#endif

float rmask(vec2 p, vec4 r, float soft) {
	vec2 a = smoothstep(r.xy - soft, r.xy + soft, p);
	vec2 b = 1.0 - smoothstep(r.zw - soft, r.zw + soft, p);
	return a.x * a.y * b.x * b.y;
}

// rgb: ground colour (linear). a: "lawn" factor, 1 where long or mown grass gets blade detail, 0 on
// gravel, paths and farmland.
vec4 terrain_color(vec2 p, float lushness) {
	float big = fbm2(p * 0.012);
	float mid = n2(p * 0.18);
	vec3 col = mix(U(grass_a), U(grass_b), smoothstep(0.3, 0.7, big));
	col = mix(col, U(grass_dry), smoothstep(0.55, 0.85, mid) * 0.35 * (1.0 - lushness * 0.5));
	float infield = rmask(p, field_rect, 6.0);
	// mowing stripes (lawn-mower passes) in the flying field
	float stripe = 0.5 + 0.5 * sin(p.x * 0.4488);
	col *= mix(1.0, mix(0.975, 1.025, stripe), infield * 0.75);
	float grw = rmask(p, grass_rwy, 1.5);
	float stripe2 = 0.5 + 0.5 * sin(p.x * 0.8976);
	col = mix(col, U(grass_a) * mix(1.0, 1.06, stripe2), grw * 0.8);
	// rough outer meadow & farmland beyond the field
	vec2 cell = floor((p + vec2(37.0, 11.0)) / vec2(95.0, 70.0));
	float ch = h2(cell);
	vec3 farm = U(grass_b);
	if (ch < 0.25) farm = vec3(0.55, 0.48, 0.24);
	else if (ch < 0.45) farm = vec3(0.34, 0.40, 0.14);
	else if (ch < 0.55) farm = vec3(0.33, 0.25, 0.16);
	else if (ch < 0.8) farm = U(grass_a) * 0.95;
	else farm = U(forest) * 1.2;
	vec2 fc = fract((p + vec2(37.0, 11.0)) / vec2(95.0, 70.0));
	float hedge = 1.0 - smoothstep(0.0, 0.04, min(min(fc.x, 1.0 - fc.x), min(fc.y, 1.0 - fc.y)));
	float farmzone = smoothstep(260.0, 380.0, length(p));
	farm = mix(farm, U(forest) * 1.1, hedge * 0.8);
	farm *= 0.9 + 0.2 * n2(p * 0.05 + ch * 10.0);
	col = mix(col, farm, farmzone);
	// forest patches on the hills
	float fm = smoothstep(0.52, 0.6, fbm2(p * 0.004 + vec2(3.1, 7.7)));
	col = mix(col, U(forest), fm * smoothstep(300.0, 450.0, length(p)));
	// gravel parking & worn paths
	float gr = rmask(p, gravel_rect, 1.0);
	col = mix(col, U(gravel), gr);
	float pathm = rmask(p, vec4(-43.5, 6.0, -36.5, 20.0), 0.8);
	col = mix(col, U(dirt), pathm * 0.85);
	// wear in front of pilot stations
	float wear = rmask(p, vec4(-22.0, 13.5, 22.0, 18.0), 2.5);
	col = mix(col, mix(col, U(dirt), 0.45), wear * smoothstep(0.35, 0.7, mid));
	float lawn = clamp(1.0 - gr - pathm, 0.0, 1.0) * (1.0 - farmzone);
	return vec4(col, lawn);
}
