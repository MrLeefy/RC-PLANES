shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
// Ground with its colour baked into textures at load (scripts/world/terrain_bake.gd). Per pixel this is
// five texture reads instead of the ~1000 arithmetic operations of the procedural shader, which matters on
// phone GPUs where the ground covers about half of the screen.
global uniform vec3 cam_pos;
uniform sampler2D bake_near : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D bake_far : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 near_rect = vec4(-256.0, -128.0, 512.0, 256.0);    // world x, z of the corner, then size
uniform vec4 far_rect = vec4(-1200.0, -1200.0, 2400.0, 2400.0);
uniform float lushness = 1.0;
varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 un = (p - near_rect.xy) / near_rect.zw;
	vec4 far_c = texture(bake_far, (p - far_rect.xy) / far_rect.zw);
	vec4 near_c = texture(bake_near, clamp(un, 0.0, 1.0));
	float inside = step(0.0, un.x) * step(un.x, 1.0) * step(0.0, un.y) * step(un.y, 1.0);
	vec4 tc = mix(far_c, near_c, inside);
	// the bake assumes full lushness; lower values shift toward dry, yellowish grass
	tc.rgb *= mix(vec3(1.0), vec3(1.05, 1.0, 0.9), clamp((1.0 - lushness) * 2.0, 0.0, 1.0));
	// fine tiling detail: r = blade streaks, g/b = clumps and grain. Mip filtering fades it by itself.
	vec3 d1 = texture(detail_tex, p * 1.44).rgb;
	vec3 d2 = texture(detail_tex, p * 0.17).rgb;
	vec3 col = tc.rgb * (0.97 + 0.06 * d2.b);
	col *= mix(1.0, (0.84 + 0.32 * d1.r) * (0.9 + 0.2 * d2.g), tc.a);
	ALBEDO = col;
	ROUGHNESS = 0.96;
	SPECULAR = 0.25;
	float dist = length(wpos - cam_pos);
	vec3 g = vec3(d2.g - 0.5, 0.0, d2.b - 0.5) * 0.18 * (1.0 - smoothstep(20.0, 80.0, dist));
	NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * g);
}
