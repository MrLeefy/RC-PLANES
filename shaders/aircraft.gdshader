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
// 0 = performance (base look), 1 = high, 2 = ultra; set from the graphics quality
global uniform float gfx_detail;

varying vec3 opos;
varying vec3 onrm;
varying float wny;

void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
	wny = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz).y;
}

void fragment() {
	vec3 base = COLOR.rgb;
	float paint = COLOR.a;
	float r = rough;
	float m = 0.0;
	vec3 g = vec3(0.0);
	float pixel = max(max(fwidth(opos.x), fwidth(opos.y)), fwidth(opos.z));
	float micro = 1.0 - smoothstep(0.0015, 0.012, pixel);
	float hi = step(0.5, gfx_detail);          // high quality extras
	float ultra = step(1.5, gfx_detail);       // ultra extras
	float seam_zone = 0.0;
	if (kind == 0) {
		float b = mix(0.5, n3(opos * 170.0), micro);
		base *= 0.978 + 0.044 * b;
		r = rough + (b - 0.5) * 0.09;
		g = vec3(b - 0.5, (n3(opos * 170.0 + 5.3) - 0.5) * micro, 0.0) * bump;
	} else if (kind == 1) {
		float w = n3(opos * vec3(9.0, 40.0, 9.0));
		g = vec3(w - 0.5, 0.0, n3(opos * 11.0) - 0.5) * bump * 0.35;
		r = rough + (w - 0.5) * 0.06;
	} else if (kind == 3) {
		vec2 w = UV * 140.0;
		float weave = 1.0 - smoothstep(0.25, 0.8, max(fwidth(w.x), fwidth(w.y)));
		float cell = floor(w.x) + floor(w.y);
		bool hor = mod(cell, 4.0) < 2.0;
		float tow = sin(fract(hor ? w.x : w.y) * 3.14159);
		base = mix(vec3(0.032,0.034,0.039), mix(vec3(0.012, 0.013, 0.015), vec3(0.06, 0.062, 0.068), tow * (hor ? 1.0 : 0.6)), weave);
		r = 0.35 + (0.07 - 0.14 * tow) * weave;
	} else if (kind == 4 || kind == 8 || kind == 2) {
		// riveted skin: oil-canned brightness variation, seam grooves (albedo + bevelled normals), rivet dimples
		vec3 q = opos * vec3(8.0, 9.0, 6.5);
		vec3 cid = floor(q);
		float pv = h3(cid);
		vec3 fq = fract(q);
		vec3 d = 0.5 - abs(fq - 0.5);
		vec3 w = fwidth(q) * 0.9 + 0.002;
		float lx = 1.0 - smoothstep(0.0, w.x, d.x - 0.002);
		float lz = 1.0 - smoothstep(0.0, w.z, d.z - 0.002);
		// fade seams out when they get sub-pixel to avoid banding/moire at distance
		float fade = 1.0 - smoothstep(0.08, 0.25, max(fwidth(q.x), fwidth(q.z)));
		float line = max(lx, lz) * panel_lines * fade;
		seam_zone = max(1.0 - smoothstep(0.0, 0.05, d.x), 1.0 - smoothstep(0.0, 0.05, d.z)) * panel_lines * fade;
		float riv = 0.0;
		vec3 rq = fract(q * 7.0) - 0.5;
		riv = (1.0 - smoothstep(0.08, 0.14, length(rq.xz))) * max(1.0 - smoothstep(0.0, 0.03, d.x), 1.0 - smoothstep(0.0, 0.03, d.z)) * panel_lines;
		if (kind == 4) {
			m = mix(0.78, 0.0, paint);
			r = mix(0.34 + pv * 0.12, 0.42, paint);
			base *= mix(0.92 + pv * 0.12, 1.0, paint);
		} else {
			r = rough + (pv - 0.5) * 0.08;
			base *= 0.96 + pv * 0.06;
		}
		base *= 1.0 - line * 0.28;
		base *= 1.0 + riv * 0.18 * micro;
		// bevelled seam normals: the groove catches the light on one side and shades the other
		float sx = (fq.x < 0.5 ? 1.0 : -1.0) * (1.0 - smoothstep(0.0, w.x * 2.2, d.x));
		float sz = (fq.z < 0.5 ? 1.0 : -1.0) * (1.0 - smoothstep(0.0, w.z * 2.2, d.z));
		g += vec3(sx, 0.0, sz) * 0.55 * panel_lines * fade * hi;
		// rivet domes
		vec2 rd = rq.xz;
		float rr = length(rd);
		g += vec3(rd.x, 0.0, rd.y) / (rr + 0.001) * (1.0 - smoothstep(0.05, 0.13, rr)) * seam_zone * 0.7 * micro * hi;
		if (kind == 4) {
			// brushed metal: streaks follow the airflow (aircraft z axis); polished panels get a soft, stretched highlight
			float st = n3(vec3(opos.x * 160.0, opos.y * 160.0, opos.z * 9.0));
			r += (st - 0.5) * 0.10 * hi;
			base *= 1.0 + (st - 0.5) * 0.06 * hi * (1.0 - paint);
		}
	} else if (kind == 5) {
		vec2 w = UV * 420.0;
		float wv = sin(w.x) * sin(w.y) * (1.0 - smoothstep(0.4, 1.6, max(fwidth(w.x), fwidth(w.y))));
		base *= 0.98 + wv * 0.02;
		r = rough + wv * 0.05;
		g += vec3(sin(w.x), 0.0, sin(w.y)) * 0.05 * micro * hi * (1.0 - smoothstep(0.003, 0.02, pixel));
	} else if (kind == 6) {
		float b = mix(0.5, n3(opos * 90.0), micro);
		base *= 0.9 + b * 0.15;
		r = rough;
		g += vec3(b - 0.5, 0.0, n3(opos * 90.0 + 7.0) - 0.5) * 0.25 * micro * hi;
	}
	// paint finish: fine orange peel, airflow-aligned grime streaks and soot, underside soiling, edge sheen
	if (kind == 1 || kind == 2 || kind == 7 || kind == 8) {
		g += vec3(n3(opos * 260.0) - 0.5, 0.0, n3(opos * 260.0 + 9.0) - 0.5) * 0.05 * micro * hi * (1.0 - smoothstep(0.003, 0.02, pixel));
	}
	if (hi > 0.5 && kind != 3 && kind != 9 && kind != 6) {
		float lo = n3(vec3(opos.x * 6.0, opos.y * 6.0, opos.z * 1.1));                // broad fading
		float streak = n3(vec3(opos.x * 45.0, opos.y * 45.0, opos.z * 2.6));        // thin streaks along the flow
		float grime = smoothstep(0.55, 0.9, streak * 0.7 + lo * 0.5) * (0.35 + 0.65 * clamp(0.5 - wny * 0.6, 0.0, 1.0));
		base *= 1.0 - grime * (0.045 + 0.05 * ultra);
		r += grime * 0.08;
		base *= 0.96 + 0.04 * clamp(wny * 0.5 + 0.5, 0.0, 1.0);                       // underside sits a little darker
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
	if (hi > 0.5 && (kind == 0 || kind == 1 || kind == 5)) {
		RIM = 0.18;
		RIM_TINT = 0.6;
	}
	if (dot(g, g) > 0.0) {
		NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX * MODEL_MATRIX) * g);
	}
}
