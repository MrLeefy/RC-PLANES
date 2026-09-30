shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;
#include "res://shaders/common.gdshaderinc"
global uniform vec2 wind_dir;
global uniform float wind_strength;
global uniform float wind_gust;
global uniform vec3 cam_pos;
global uniform float grass_fade;
uniform vec3 base_col : source_color = vec3(0.16, 0.23, 0.10);
uniform vec3 tip_col : source_color = vec3(0.39, 0.48, 0.24);
uniform vec3 dry_col : source_color = vec3(0.57, 0.52, 0.33);
varying float hfrac;
varying float vari;
void vertex() {
	vec3 org = MODEL_MATRIX[3].xyz;
	float d = length(org - cam_pos);
	float fade = 1.0 - smoothstep(grass_fade * 0.65, grass_fade, d);
	hfrac = clamp(VERTEX.y / 0.2, 0.0, 1.0);
	VERTEX.y *= fade;
	float ws = wind_strength * (0.6 + 0.4 * wind_gust);
	float ph = TIME * 2.2 + org.x * 0.6 + org.z * 0.45;
	vec2 b = wind_dir * (ws * 0.09 + sin(ph) * 0.03 * (0.3 + ws)) * hfrac * hfrac;
	VERTEX.xz += (transpose(mat3(MODEL_MATRIX)) * vec3(b.x, 0.0, b.y)).xz;
	vari = h2(org.xz * 1.7);
	// face normals roughly up so the lawn shades like a surface
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.7));
}
void fragment() {
	vec3 c = mix(base_col, tip_col, hfrac);
	c = mix(c, dry_col, step(0.85, vari) * hfrac * 0.6);
	c *= (0.90 + 0.20 * vari) * COLOR.rgb;
	ALBEDO = c;
	ROUGHNESS = 0.9;
	BACKLIGHT = c * 0.4;
	AO = mix(0.45, 1.0, hfrac);
}
