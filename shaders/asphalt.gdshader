shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
uniform float half_len = 70.0;
uniform float half_wid = 6.0;
uniform vec3 base_col : source_color = vec3(0.205, 0.215, 0.225);
uniform sampler2D aggregate_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D aggregate_normal_tex : filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = wpos.xz;
	float ax = abs(p.x);
	float az = abs(p.y);
	vec2 footprint = max(fwidth(p), vec2(0.0001));
	float pixel = max(footprint.x, footprint.y);
	float detail = 1.0 - smoothstep(0.004, 0.025, pixel);
	// One tile is ~1.15 m, with approximately 150 irregular aggregate cells.
	float aggregate = texture(aggregate_tex, p * 0.87).r;
	float agg = mix(0.5, aggregate, detail);
	vec3 col = base_col * (0.96 + 0.08 * agg);
	float rough = 0.89 + (agg - 0.5) * 0.06;
	// repaired patches (darker, newer)
	float patch_m = smoothstep(0.65, 0.76, n2(p * vec2(0.065, 0.14) + 8.3));
	patch_m *= smoothstep(0.25, 0.55, n2(p * 0.45));
	col *= 1.0 - patch_m * 0.22;
	float big = fbm2(p * 0.08);
	col *= 0.93 + 0.14 * big;
	// longitudinal paving seams + transverse joints
	float seam = 1.0 - smoothstep(0.0, max(0.012, footprint.x * 1.5), abs(fract(p.x / 25.0 + 0.5) - 0.5) * 25.0);
	float seam2 = 1.0 - smoothstep(0.0, max(0.012, footprint.y * 1.5), abs(p.y));
	col *= 1.0 - (seam * 0.18 + seam2 * 0.08);
	// cracks (voronoi edges, only in some areas)
	vec2 v = vor2(p * vec2(0.55, 0.9));
	float crack = (1.0 - smoothstep(0.0, max(0.012, pixel), v.y)) * (1.0 - smoothstep(0.025, 0.15, pixel)) * smoothstep(0.62, 0.78, n2(p * 0.07 + 3.0));
	col *= 1.0 - crack * 0.45;
	// tyre rubber in the touchdown zones
	float tdz = (1.0 - smoothstep(52.0, 58.0, ax)) * smoothstep(30.0, 38.0, ax) * (1.0 - smoothstep(1.5, 3.2, az));
	float streak = n2(vec2(p.x * 0.05, p.y * 6.0));
	col *= 1.0 - tdz * streak * 0.22;
	// edge deterioration + grass bleed
	float edge = smoothstep(half_wid - 0.6, half_wid, az);
	col = mix(col, vec3(0.28, 0.27, 0.22) * (0.8 + 0.4 * agg), edge * smoothstep(0.35, 0.75, n2(p * 1.3)));
	// markings
	// anti-aliased markings (box masks softened by screen-space derivatives)
	vec2 fw = max(fwidth(p), vec2(0.002));
	float fwx = fw.x;
	float fwz = fw.y;
	float paint = 0.0;
	paint += smoothstep(half_wid - 0.45 - fwz, half_wid - 0.45 + fwz, az) * (1.0 - smoothstep(half_wid - 0.25 - fwz, half_wid - 0.25 + fwz, az)) * step(ax, half_len - 1.0);
	float dash = smoothstep(0.0, fwx / 7.0 * 2.0, fract(p.x / 7.0)) * (1.0 - smoothstep(0.55 - fwx / 7.0, 0.55 + fwx / 7.0, fract(p.x / 7.0)));
	paint += (1.0 - smoothstep(0.15 - fwz, 0.15 + fwz, az)) * dash * step(ax, half_len - 10.0) * step(12.0, ax);
	float thr = smoothstep(half_len - 6.0 - fwx, half_len - 6.0 + fwx, ax) * (1.0 - smoothstep(half_len - 2.0 - fwx, half_len - 2.0 + fwx, ax)) * step(az, half_wid - 0.9);
	float bars = fract((p.y + 0.3) / 1.1);
	paint += thr * (1.0 - smoothstep(0.62 - fwz, 0.62 + fwz, bars)) * smoothstep(0.0, fwz * 2.0, bars);
	paint += smoothstep(44.0 - fwx, 44.0 + fwx, ax) * (1.0 - smoothstep(50.0 - fwx, 50.0 + fwx, ax)) * smoothstep(1.2 - fwz, 1.2 + fwz, az) * (1.0 - smoothstep(2.3 - fwz, 2.3 + fwz, az));
	paint = clamp(paint, 0.0, 1.0);
	float wear_detail = mix(0.5, n2(p * 9.0), 1.0 - smoothstep(0.015, 0.08, pixel));
	float worn = smoothstep(0.25, 0.6, wear_detail) * 0.13 + 0.87;
	col = mix(col, vec3(0.82, 0.82, 0.8) * worn, paint * worn);
	rough = mix(rough, 0.72, paint);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.32;
	vec2 grain_normal = texture(aggregate_normal_tex, p * 0.87).rg * 2.0 - 1.0;
	vec3 g = vec3(grain_normal.x, 0.0, grain_normal.y) * 0.13 * detail * (1.0 - paint * 0.4);
	NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * g);
}
