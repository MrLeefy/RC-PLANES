shader_type canvas_item;
render_mode blend_disabled;
// One-off bake of the cloud noise used by sky.gdshader: a tileable value-noise fbm. Evaluating fbm per sky
// pixel (about 20 hashes) was a measurable fragment cost on phones, where the sky covers around half of the
// screen. r: 4 octaves starting at 16 cells per tile, g: fine breakup at 64 cells per tile.
#include "res://shaders/common.gdshaderinc"

float hp(vec2 i, float period) {
	return h2(mod(i, period));
}

float np(vec2 x, float period) {
	vec2 i = floor(x);
	vec2 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hp(i, period), hp(i + vec2(1, 0), period), f.x), mix(hp(i + vec2(0, 1), period), hp(i + vec2(1, 1), period), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	float a = 0.5;
	float s = 0.0;
	float period = 16.0;
	for (int k = 0; k < 4; k++) {
		s += a * np(uv * period + vec2(float(k) * 5.3, float(k) * 2.1), period);
		period *= 2.0;
		a *= 0.5;
	}
	float fine = np(uv * 64.0 + vec2(11.7, 3.3), 64.0);
	COLOR = vec4(s, fine, 0.0, 1.0);
}
