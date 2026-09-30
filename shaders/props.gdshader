shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
// 0 painted, 1 wood, 2 corrugated metal, 3 concrete, 4 car paint, 5 dark plastic/rubber,
// 6 fabric, 7 dark glass, 8 bare metal
uniform int kind = 0;
varying vec3 wpos;
varying vec3 wn;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}
void fragment() {
	vec3 c = COLOR.rgb;
	float r = 0.7;
	float m = 0.0;
	vec3 g = vec3(0.0);
	float pixel = max(max(fwidth(wpos.x), fwidth(wpos.y)), fwidth(wpos.z));
	float micro = 1.0 - smoothstep(0.003, 0.018, pixel);
	if (kind == 0) {
		c *= 0.92 + 0.12 * n3(wpos * 3.0);
		r = 0.75;
	} else if (kind == 1) {
		float grain = n3(wpos * vec3(3.0, 28.0, 3.0) + vec3(wpos.y * 2.0));
		float edge = fract(wpos.y * 6.0 + wpos.x * 0.001);
		float plank = smoothstep(0.95, 0.98, edge) * (1.0 - smoothstep(0.01,0.08,pixel));
		c *= (0.78 + 0.35 * grain) * (1.0 - plank * 0.4);
		r = 0.85;
		g = vec3(grain - 0.5, 0.0, 0.0) * 0.25;
	} else if (kind == 2) {
		float rib = sin((wpos.x + wpos.z) * 26.0) * (1.0 - smoothstep(0.015,0.07,pixel));
		g = vec3(rib, 0.0, -rib) * 0.18;
		c *= 0.9 + 0.12 * n3(wpos * 0.8);
		r = 0.45;
		m = 0.6;
	} else if (kind == 3) {
		c *= 0.85 + 0.25 * n3(wpos * 4.0) * n3(wpos * 17.0 + 3.0);
		r = 0.92;
	} else if (kind == 4) {
		r = 0.22;
		m = 0.15;
		CLEARCOAT = 0.9;
		CLEARCOAT_ROUGHNESS = 0.08;
	} else if (kind == 5) {
		r = 0.82;
	} else if (kind == 6) {
		c *= 0.9 + 0.1 * sin(wpos.x * 300.0) * sin(wpos.y * 300.0) * micro;
		r = 0.92;
	} else if (kind == 7) {
		c = vec3(0.02, 0.025, 0.03);
		r = 0.06;
		m = 0.3;
		SPECULAR = 0.9;
	} else if (kind == 8) {
		r = 0.35;
		m = 0.85;
	}
	ALBEDO = c;
	ROUGHNESS = r;
	METALLIC = m;
	if (dot(g, g) > 0.0) {
		NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * g);
	}
}
