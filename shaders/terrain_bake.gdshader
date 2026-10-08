shader_type canvas_item;
render_mode blend_disabled;
// One-off bake of terrain_color() into a texture: rgb = ground colour (sRGB encoded, so it can be sampled
// with source_color), a = lawn factor. Rendered into a SubViewport by scripts/world/terrain_bake.gd.
#define TERRAIN_BAKE
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/terrain_color.gdshaderinc"
uniform vec4 rect = vec4(-1200.0, -1200.0, 2400.0, 2400.0);   // world x, z of the corner, then size

vec3 lin_to_srgb(vec3 c) {
	return mix(c * 12.92, 1.055 * pow(max(c, vec3(0.0031308)), vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

void fragment() {
	vec2 p = rect.xy + UV * rect.zw;
	vec4 tc = terrain_color(p, 1.0);
	COLOR = vec4(lin_to_srgb(tc.rgb), tc.a);
}
