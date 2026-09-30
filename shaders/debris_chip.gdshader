shader_type spatial;
#include "res://shaders/common.gdshaderinc"
instance uniform vec3 tint : source_color = vec3(0.8);
varying vec3 opos;
void vertex() { opos = VERTEX; }
void fragment() {
	float b = n3(opos * 60.0);
	ALBEDO = tint * (0.8 + 0.3 * b);
	ROUGHNESS = 0.75;
}