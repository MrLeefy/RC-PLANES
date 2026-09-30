shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, specular_schlick_ggx;
uniform vec3 tint : source_color = vec3(0.1, 0.12, 0.15);
uniform float opacity = 0.62;
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = tint * 0.35;
	ROUGHNESS = 0.03;
	METALLIC = 0.0;
	SPECULAR = 1.0;
	ALPHA = clamp(mix(opacity, 0.97, f), 0.0, 1.0);
}
