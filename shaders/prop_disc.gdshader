shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, diffuse_lambert, specular_disabled;
// UV.x = radius fraction (0 hub .. 1 tip), UV.y = angle fraction
uniform vec3 blade_color : source_color = vec3(0.05);
uniform vec3 tip_color : source_color = vec3(0.9);
uniform float tip_band = 0.0;
uniform float blades = 2.0;
instance uniform float blur = 0.0;
void fragment() {
	float r = UV.x;
	float chord = mix(1.0, 0.55, r);
	float a = blur * (0.10 + 0.10 * chord) * smoothstep(0.02, 0.12, r) * (1.0 - smoothstep(0.96, 1.0, r));
	float tip = step(1.0 - tip_band, r) * tip_band;
	float streak = 0.9 + 0.1 * sin(UV.y * 6.2831 * blades * 3.0 + r * 9.0);
	ALBEDO = mix(blade_color, tip_color, tip > 0.0 ? 1.0 : 0.0);
	ALPHA = a * streak * (tip > 0.0 ? 1.6 : 1.0);
	ROUGHNESS = 0.6;
}