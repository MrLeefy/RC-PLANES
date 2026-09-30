shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
global uniform vec3 cam_pos;
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
uniform float lushness = 1.0;
varying vec3 wpos;

float rmask(vec2 p, vec4 r, float soft) {
	vec2 a = smoothstep(r.xy - soft, r.xy + soft, p);
	vec2 b = 1.0 - smoothstep(r.zw - soft, r.zw + soft, p);
	return a.x * a.y * b.x * b.y;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float dist = length(wpos - cam_pos);
	float big = fbm2(p * 0.012);
	float mid = n2(p * 0.18);
	float footprint = max(fwidth(p.x), fwidth(p.y));
	float fine = mix(0.5, n2(p * 2.7), 1.0 - smoothstep(0.10, 0.35, footprint));
	vec3 col = mix(grass_a, grass_b, smoothstep(0.3, 0.7, big));
	col = mix(col, grass_dry, smoothstep(0.55, 0.85, mid) * 0.35 * (1.0 - lushness * 0.5));
	float infield = rmask(p, field_rect, 6.0);
	// mowing stripes (lawn-mower passes) in the flying field
	float stripe = 0.5 + 0.5 * sin(p.x * 0.4488);
	col *= mix(1.0, mix(0.975, 1.025, stripe), infield * (1.0 - smoothstep(60.0, 260.0, dist) * 0.5));
	float grw = rmask(p, grass_rwy, 1.5);
	float stripe2 = 0.5 + 0.5 * sin(p.x * 0.8976);
	col = mix(col, grass_a * mix(1.0, 1.06, stripe2), grw * 0.8);
	// rough outer meadow & farmland beyond the field
	float outside = 1.0 - infield;
	vec2 cell = floor((p + vec2(37.0, 11.0)) / vec2(95.0, 70.0));
	float ch = h2(cell);
	vec3 farm = grass_b;
	if (ch < 0.25) farm = vec3(0.55, 0.48, 0.24);
	else if (ch < 0.45) farm = vec3(0.34, 0.40, 0.14);
	else if (ch < 0.55) farm = vec3(0.33, 0.25, 0.16);
	else if (ch < 0.8) farm = grass_a * 0.95;
	else farm = forest * 1.2;
	vec2 fc = fract((p + vec2(37.0, 11.0)) / vec2(95.0, 70.0));
	float hedge = 1.0 - smoothstep(0.0, 0.04, min(min(fc.x, 1.0 - fc.x), min(fc.y, 1.0 - fc.y)));
	float farmzone = smoothstep(260.0, 380.0, length(p));
	farm = mix(farm, forest * 1.1, hedge * 0.8);
	farm *= 0.9 + 0.2 * n2(p * 0.05 + ch * 10.0);
	col = mix(col, farm, farmzone);
	// forest patches on the hills
	float fm = smoothstep(0.52, 0.6, fbm2(p * 0.004 + vec2(3.1, 7.7)));
	col = mix(col, forest, fm * smoothstep(300.0, 450.0, length(p)));
	// gravel parking & worn paths
	float gr = rmask(p, gravel_rect, 1.0);
	col = mix(col, gravel * (0.8 + 0.4 * fine), gr);
	float pathm = rmask(p, vec4(-43.5, 6.0, -36.5, 20.0), 0.8);
	col = mix(col, dirt * (0.85 + 0.3 * fine), pathm * 0.85);
	// wear in front of pilot stations
	float wear = rmask(p, vec4(-22.0, 13.5, 22.0, 18.0), 2.5);
	col = mix(col, mix(col, dirt, 0.45), wear * smoothstep(0.35, 0.7, mid));
	col *= 0.97 + 0.06 * fine;
	ALBEDO = col;
	ROUGHNESS = 0.96;
	SPECULAR = 0.25;
	vec3 g = vec3(n2(p * 3.1) - 0.5, 0.0, n2(p * 3.1 + 11.0) - 0.5) * 0.18 * (1.0 - smoothstep(20.0, 80.0, dist)) * (1.0 - smoothstep(0.10, 0.3, footprint));
	NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * g);
}
