shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
global uniform vec2 wind_dir;
global uniform float wind_strength;
global uniform float wind_gust;
uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 tint_a : source_color = vec3(0.35, 0.5, 0.2);
uniform vec3 tint_b : source_color = vec3(0.25, 0.4, 0.15);
uniform float sway = 1.0;
varying float vari;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 org = MODEL_MATRIX[3].xyz;
	float s2 = dot(MODEL_MATRIX[0].xyz, MODEL_MATRIX[0].xyz);
	float h = max(wp.y - org.y, 0.0);
	float ws = wind_strength * (0.7 + 0.3 * wind_gust);
	float t = TIME;
	float osc = sin(t * 1.1 + org.x * 0.21 + org.z * 0.17) * 0.6 + sin(t * 2.7 + org.x) * 0.25;
	vec2 bend = wind_dir * (ws * 0.025 * h + osc * 0.012 * h * (0.3 + ws)) * sway;
	vec3 flutter = vec3(sin(t * 7.0 + wp.y * 3.0 + wp.x), sin(t * 6.3 + wp.z * 2.0), cos(t * 7.7 + wp.x * 2.0)) * 0.025 * (0.2 + ws) * sway;
	vec3 disp = vec3(bend.x, 0.0, bend.y) + flutter;
	VERTEX += transpose(mat3(MODEL_MATRIX)) * disp / s2;
	vari = h2(org.xz * 0.37);
}
void fragment() {
	vec4 t = texture(leaf_tex, UV);
	vec3 tint = mix(tint_a, tint_b, vari) * (0.85 + 0.3 * COLOR.r);
	ALBEDO = t.rgb * tint;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.45;
	ROUGHNESS = 0.75;
	SPECULAR = 0.3;
	BACKLIGHT = ALBEDO * 0.55;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}