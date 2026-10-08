shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Procedural ground: used only when the baked ground (terrain_baked.gdshader) is unavailable, for example
// on a headless run without a GPU. Same colour function as the bake, evaluated per pixel.
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/terrain_color.gdshaderinc"
global uniform vec3 cam_pos;
uniform float lushness = 1.0;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	float dist = length(wpos - cam_pos);
	float footprint = max(fwidth(p.x), fwidth(p.y));
	float fine = mix(0.5, n2(p * 2.7), 1.0 - smoothstep(0.10, 0.35, footprint));
	vec4 tc = terrain_color(p, lushness);
	vec3 col = tc.rgb * (0.97 + 0.06 * fine);
	// lawn micro-structure: blade streaks + light/dark clumps, faded out when sub-pixel
	float blade_fade = 1.0 - smoothstep(0.012, 0.09, footprint);
	float bl = n2(p * vec2(46.0, 38.0)) * 0.55 + n2(p * vec2(120.0, 95.0)) * 0.45;
	float clump = n2(p * 1.35 + 4.2) * 0.6 + n2(p * 4.7) * 0.4;
	col *= mix(1.0, (0.84 + 0.32 * bl) * (0.9 + 0.2 * clump), blade_fade * tc.a);
	ALBEDO = col;
	ROUGHNESS = 0.96;
	SPECULAR = 0.25;
	vec3 g = vec3(n2(p * 3.1) - 0.5, 0.0, n2(p * 3.1 + 11.0) - 0.5) * 0.18 * (1.0 - smoothstep(20.0, 80.0, dist)) * (1.0 - smoothstep(0.10, 0.3, footprint));
	NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * g);
}
