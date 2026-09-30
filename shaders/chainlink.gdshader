shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform vec3 wire : source_color = vec3(0.12, 0.14, 0.12);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	// diamond wire pattern in the plane of the fence
	float u = (wpos.x + wpos.z) * 18.0;
	float v = wpos.y * 18.0;
	vec2 d1 = vec2(u + v, u - v);
	vec2 f = abs(fract(d1 * 0.5) - 0.5);
	float w = min(f.x, f.y);
	float dist_fade = smoothstep(8.0, 40.0, length(wpos - CAMERA_POSITION_WORLD));
	float line = 1.0 - smoothstep(0.03, 0.07 + dist_fade * 0.1, w);
	ALBEDO = wire;
	ROUGHNESS = 0.6;
	METALLIC = 0.4;
	ALPHA = line * (1.0 - dist_fade * 0.75);
	ALPHA_SCISSOR_THRESHOLD = 0.3;
}