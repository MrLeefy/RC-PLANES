shader_type spatial;
render_mode diffuse_burley;
#include "res://shaders/common.gdshaderinc"
global uniform vec2 wind_dir;
global uniform float wind_strength;
varying vec3 opos;
void vertex() {
	opos = VERTEX;
	vec3 org = MODEL_MATRIX[3].xyz;
	float h = max(VERTEX.y, 0.0);
	float s2 = dot(MODEL_MATRIX[0].xyz, MODEL_MATRIX[0].xyz);
	vec2 bend = wind_dir * wind_strength * 0.012 * h * h * 0.1;
	VERTEX += transpose(mat3(MODEL_MATRIX)) * vec3(bend.x, 0.0, bend.y) / s2;
}
void fragment() {
	float s = n3(opos * vec3(16.0, 2.5, 16.0));
	float pixel = max(max(fwidth(opos.x), fwidth(opos.y)), fwidth(opos.z));
	float detail = 1.0 - smoothstep(0.005, 0.04, pixel);
	float f = mix(0.5, n3(opos * 40.0), detail);
	ALBEDO = COLOR.rgb * (0.7 + 0.45 * s) * (0.9 + 0.2 * f);
	ROUGHNESS = 0.95;
	vec3 g = vec3(s - 0.5, 0.0, f - 0.5) * 0.3 * detail;
	NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX * MODEL_MATRIX) * g);
}
