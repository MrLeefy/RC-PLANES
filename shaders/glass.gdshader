shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
uniform vec3 tint : source_color = vec3(0.1, 0.12, 0.15);
uniform float opacity = 0.62;
global uniform float gfx_detail;
varying vec3 opos;
void vertex() {
	opos = VERTEX;
}
void fragment() {
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float f = pow(1.0 - ndv, 3.0);
	float hi = step(0.5, gfx_detail);
	// faint scratches and a slightly uneven tint, like cast acrylic
	float scr = smoothstep(0.86, 0.95, n3(vec3(opos.x * 140.0, opos.y * 6.0, opos.z * 140.0))) * 0.5;
	float uneven = n3(opos * 12.0);
	ALBEDO = tint * (0.30 + 0.12 * uneven * hi);
	ROUGHNESS = mix(0.03, 0.12, scr * hi);
	METALLIC = 0.0;
	SPECULAR = 1.0;
	RIM = 0.15 * hi;
	RIM_TINT = 0.2;
	ALPHA = clamp(mix(opacity, 0.97, f) + scr * 0.08 * hi, 0.0, 1.0);
}
