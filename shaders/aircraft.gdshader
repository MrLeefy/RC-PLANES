shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"

// kind: 0 foam, 1 film-covered balsa, 2 composite, 3 carbon, 4 polished metal,
//       5 fabric, 6 rubber, 7 plastic, 8 painted metal, 9 cockpit/dark
uniform int kind = 0;
uniform float rough = 0.55;
uniform float coat = 0.0;
uniform float bump = 0.25;
uniform float panel_lines = 0.0;
uniform vec3 substrate : source_color = vec3(0.85, 0.85, 0.8);
instance uniform float damage = 0.0;
instance uniform float dirt = 0.0;

varying vec3 opos;
varying vec3 onrm;

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
}

void fragment() {
	vec3 base = COLOR.rgb;
	float paint = COLOR.a;
	float r = rough;
	float m = 0.0;
	vec3 g = vec3(0.0);
	float pixel = max(max(fwidth(opos.x), fwidth(opos.y)), fwidth(opos.z));
	float micro = 1.0 - smoothstep(0.0015, 0.012, pixel);
	if (kind == 0) {
		float b = mix(0.5, n3(opos * 170.0), micro);
		base *= 0.978 + 0.044 * b;
		r = rough + (b - 0.5) * 0.09;
		g = vec3(b - 0.5, (n3(opos * 170.0 + 5.3) - 0.5) * micro, 0.0) * bump;
	} else if (kind == 1) {
		float w = n3(opos * vec3(9.0, 40.0, 9.0));
		g = vec3(w - 0.5, 0.0, n3(opos * 11.0) - 0.5) * bump * 0.35;
		r = rough + (w - 0.5) * 0.06;
	} else if (kind == 2) {
		r = rough;
	} else if (kind == 3) {
		vec2 w = UV * 140.0;
		float weave = 1.0 - smoothstep(0.25, 0.8, max(fwidth(w.x), fwidth(w.y)));
		float cell = floor(w.x) + floor(w.y);
		bool hor = mod(cell, 4.0) < 2.0;
		float tow = sin(fract(hor ? w.x : w.y) * 3.14159);
		base = mix(vec3(0.032,0.034,0.039), mix(vec3(0.012, 0.013, 0.015), vec3(0.06, 0.062, 0.068), tow * (hor ? 1.0 : 0.6)), weave);
		r = 0.35 + (0.07 - 0.14 * tow) * weave;
	} else if (kind == 4 || kind == 8) {
		// panels: oil-canned brightness variation + seams + rivets
		vec3 q = opos * vec3(8.0, 9.0, 6.5);
		vec3 cid = floor(q);
		float pv = h3(cid);
		vec3 d = 0.5 - abs(fract(q) - 0.5);
		vec3 w = fwidth(q) * 0.9 + 0.002;
		float lx = 1.0 - smoothstep(0.0, w.x, d.x - 0.002);
		float lz = 1.0 - smoothstep(0.0, w.z, d.z - 0.002);
		// fade seams out when they get sub-pixel to avoid banding/moire at distance
		float fade = 1.0 - smoothstep(0.08, 0.25, max(fwidth(q.x), fwidth(q.z)));
		float line = max(lx, lz) * panel_lines * fade;
		float riv = 0.0;
		vec3 rq = fract(q * 7.0) - 0.5;
		riv = (1.0 - smoothstep(0.08, 0.14, length(rq.xz))) * max(1.0 - smoothstep(0.0, 0.03, d.x), 1.0 - smoothstep(0.0, 0.03, d.z)) * panel_lines;
		if (kind == 4) {
			m = mix(0.92, 0.0, paint);
			r = mix(0.20 + pv * 0.12, 0.42, paint);
			base *= mix(0.92 + pv * 0.12, 1.0, paint);
		} else {
			r = rough + (pv - 0.5) * 0.08;
			base *= 0.96 + pv * 0.06;
		}
		base *= 1.0 - line * 0.28;
		base *= 1.0 + riv * 0.18 * micro;
	} else if (kind == 5) {
		vec2 w = UV * 420.0;
		float wv = sin(w.x) * sin(w.y) * (1.0 - smoothstep(0.4, 1.6, max(fwidth(w.x), fwidth(w.y))));
		base *= 0.95 + wv * 0.05;
		r = rough + wv * 0.05;
	} else if (kind == 6) {
		float b = mix(0.5, n3(opos * 90.0), micro);
		base *= 0.9 + b * 0.15;
		r = rough;
	}
	// damage: exposed substrate, scratches, crush marks
	if (damage > 0.001) {
		float dn = n3(opos * 9.0) * 0.6 + n3(opos * 37.0) * 0.4;
		float thr = 1.0 - damage * 0.85;
		float dm = smoothstep(thr, thr + 0.05, dn);
		float ring = smoothstep(thr - 0.06, thr, dn) - dm;
		float scr = smoothstep(0.82, 0.9, n3(opos * vec3(120.0, 6.0, 120.0))) * smoothstep(0.15, 0.6, damage) * micro;
		base = mix(base, substrate, max(dm, scr * 0.6));
		base *= 1.0 - ring * 0.5;
		r = mix(r, 0.85, dm);
		m *= 1.0 - dm;
		g += vec3(dn - 0.5, 0.0, n3(opos * 37.0 + 3.0) - 0.5) * dm * 0.35 * (1.0 - smoothstep(0.004, 0.03, pixel));
	}
	if (dirt > 0.001) {
		float dd = smoothstep(0.45, 0.8, n3(opos * 14.0)) * clamp(-onrm.y * 1.5 + 0.3, 0.0, 1.0) * dirt;
		base = mix(base, vec3(0.16, 0.14, 0.08), dd);
		r = mix(r, 0.9, dd);
	}
	if (kind == 9) {
		base *= 0.18;
		r = 0.8;
	}
	ALBEDO = base;
	ROUGHNESS = clamp(r, 0.04, 1.0);
	METALLIC = m;
	if (coat > 0.0) {
		CLEARCOAT = coat;
		CLEARCOAT_ROUGHNESS = 0.12;
	}
	if (dot(g, g) > 0.0) {
		NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX * MODEL_MATRIX) * g);
	}
}