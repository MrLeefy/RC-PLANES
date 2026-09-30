shader_type sky;
#include "res://shaders/common.gdshaderinc"
uniform vec3 zenith : source_color = vec3(0.22, 0.42, 0.78);
uniform vec3 horizon : source_color = vec3(0.72, 0.80, 0.88);
uniform vec3 ground : source_color = vec3(0.32, 0.34, 0.3);
uniform vec3 sun_tint : source_color = vec3(1.0, 0.9, 0.75);
uniform float sun_disc = 1.0;
uniform float glow = 0.35;
uniform float cloud_cov = 0.45;
uniform float cloud_dark = 0.35;
uniform vec3 cloud_col : source_color = vec3(1.0, 0.98, 0.95);
uniform vec2 cloud_offset = vec2(0.0);
uniform float exposure = 1.0;

vec3 base_sky(vec3 d, vec3 sd) {
	float y = d.y;
	vec3 col = mix(horizon, zenith, pow(clamp(y, 0.0, 1.0), 0.5));
	float hz = exp(-abs(y) * 9.0);
	float sdot = max(dot(d, sd), 0.0);
	col += sun_tint * hz * pow(sdot, 3.0) * 0.55 * glow * 2.0;
	col = mix(col, ground, smoothstep(0.0, -0.08, y));
	return col;
}

void sky() {
	vec3 d = EYEDIR;
	vec3 sd = LIGHT0_DIRECTION;
	vec3 col = base_sky(d, sd);
	float sdot = max(dot(d, sd), 0.0);
	if (!AT_CUBEMAP_PASS) {
		col += sun_tint * LIGHT0_ENERGY * (smoothstep(0.99986, 0.99992, sdot) * 14.0 * sun_disc + pow(sdot, 900.0) * 0.8 * glow + pow(sdot, 90.0) * 0.12 * glow);
		if (d.y > -0.02) {
			vec2 uv = d.xz / (d.y + 0.14) * 0.9 + cloud_offset;
			float n = fbm2(uv * 1.3);
			float n2v = n2(uv * 5.0);
			float cov = smoothstep(1.0 - cloud_cov, 1.0 - cloud_cov + 0.28, n + n2v * 0.08);
			float thick = clamp((n - (1.0 - cloud_cov)) * 2.5, 0.0, 1.0);
			vec3 lit = cloud_col * mix(vec3(1.0), sun_tint, 0.5) * (0.85 + 0.6 * pow(sdot, 5.0));
			vec3 shade = mix(horizon, zenith, 0.3) * (1.0 - cloud_dark) + ground * 0.1;
			vec3 cc = mix(lit, shade, thick * cloud_dark * 1.6);
			cc += sun_tint * pow(sdot, 12.0) * (1.0 - thick) * 0.8;
			float fadeh = smoothstep(-0.02, 0.18, d.y);
			col = mix(col, cc, cov * fadeh);
		}
	} else {
		col += sun_tint * pow(sdot, 32.0) * 0.4 * glow;
		col = mix(col, cloud_col * 0.8, cloud_cov * 0.35 * smoothstep(0.0, 0.3, d.y));
	}
	COLOR = col * exposure;
}