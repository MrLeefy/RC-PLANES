class_name AircraftBuilder
extends RefCounted
## Builds an aircraft from AircraftDB data:
##  * visual component hierarchy (each structural component is its own node so it
##    can detach), control-surface pivots on true hinge lines, rotating props,
##    gear retract/slider/steer/spin nodes, labels
##  * aerodynamic panels, control-surface mixing, engines, wheels
##  * structural component list with masses, colliders and parent links
## Everything is expressed in aircraft coordinates (x right, y up, z aft; nose at z=0).

const CH_ROLL := 0
const CH_PITCH := 1
const CH_YAW := 2
const CH_FLAP := 3

var d: Dictionary
var cfg: Dictionary
var lv: Dictionary
var scheme := ""
var mk := "foam"
var lod_detail := 2   # 2 = full detail, 1 = medium (parked display), 0 = low
var comps: Array = []
var cidx: Dictionary = {}
var parts: Array = []
var surfaces: Array = []
var panels: Array = []
var engines: Array = []
var wheels: Array = []
var labels: Array = []
var fractures: Array = []
var root: Node3D
var length := 1.0
var z_split := 0.6
var z_nose := 0.1
var _wing_ctx: Dictionary = {}
var _rng := RandomNumberGenerator.new()

# ---------------------------------------------------------------- entry
func build(def: Dictionary, config: Dictionary, detail := 2) -> Dictionary:
	d = def
	cfg = config
	lod_detail = detail
	lv = d["livery"]
	scheme = String(lv.get("scheme", ""))
	mk = String(d["material"])
	length = float(d["length"])
	_rng.seed = hash(String(d["id"]))
	root = Node3D.new()
	root.name = "Visual"
	_plan_splits()
	_cg_target_z = _estimate_cg_target()
	_add_comp("fuselage", -1, "fuselage", 1.0, true)
	_build_fuselage()
	_build_canopy()
	var wi := 0
	for w in d["wings"]:
		_build_wing(w, wi)
		wi += 1
	if not (d["htail"] as Dictionary).is_empty():
		_build_htail(d["htail"])
	var vi := 0
	for v in d["vtails"]:
		_build_vtail(v, vi)
		vi += 1
	var ei := 0
	for e in d["engines"]:
		_build_engine(e, ei)
		ei += 1
	var gi := 0
	for wdef in d["gear"]["wheels"]:
		_build_wheel(wdef, gi)
		gi += 1
	_build_details()
	_build_body_panels()
	_assign_masses()
	_build_shapes()
	_finalize_meshes()
	_place_labels()
	return {
		"root": root, "comps": comps, "surfaces": surfaces, "panels": panels,
		"engines": engines, "wheels": wheels, "cg": _cg, "mass": _total_mass,
		"fractures": fractures, "mac": _mac, "length": length, "span": _max_span(), "parts": parts,
		"ballast": ballast, "payload_mass": payload_mass, "payload_kind": payload_kind,
		"radio_mass": radio_mass, "cg_free": cg_free,
	}

func _max_span() -> float:
	var s := 0.0
	for w in d["wings"]:
		s = maxf(s, float(w["span"]))
	return s

func _plan_splits() -> void:
	var tail_z := length * 0.75
	if not (d["htail"] as Dictionary).is_empty():
		tail_z = minf(tail_z, float(d["htail"]["z"]))
	for v in d["vtails"]:
		tail_z = minf(tail_z, float(v["z"]))
	var wing_te := 0.0
	for w in d["wings"]:
		wing_te = maxf(wing_te, float(w["z"]) + float(w["root"]))
	z_split = clampf(lerpf(wing_te, tail_z, 0.45), length * 0.45, length * 0.9)
	var e0: Dictionary = d["engines"][0]
	var ep: Vector3 = e0["pos"]
	if String(e0["type"]) in ["electric", "glow2", "glow4", "gas2"] and absf(ep.x) < 0.01 and ep.z < length * 0.2:
		z_nose = ep.z + length * 0.06
	else:
		z_nose = -1.0

# ---------------------------------------------------------------- components & parts
func _add_comp(id: String, parent: int, kind: String, strength_mul := 1.0, critical := false) -> int:
	var node := Node3D.new()
	node.name = id
	root.add_child(node)
	var c := {
		"id": id, "parent": parent, "kind": kind, "visual": node, "mass": 0.0, "center": Vector3.ZERO,
		"size": Vector3(0.05, 0.05, 0.05), "shapes": [], "strength": strength_mul * float(d["strength"]),
		"critical": critical, "material": mk, "aabb_min": Vector3(INF, INF, INF), "aabb_max": Vector3(-INF, -INF, -INF),
		"mass_w": 0.0, "point_masses": [],
	}
	comps.append(c)
	cidx[id] = comps.size() - 1
	var p := {"node": node, "origin": Vector3.ZERO, "kits": {}, "comp": comps.size() - 1}
	parts.append(p)
	c["part"] = parts.size() - 1
	return comps.size() - 1

func _new_part(comp: int, parent_part: int, origin: Vector3, name := "part") -> int:
	var pp: Dictionary = parts[parent_part]
	var node := Node3D.new()
	node.name = name
	node.position = origin - (pp["origin"] as Vector3)
	(pp["node"] as Node3D).add_child(node)
	parts.append({"node": node, "origin": origin, "kits": {}, "comp": comp})
	return parts.size() - 1

func _kit(part: int, key: String) -> MeshKit:
	var kits: Dictionary = parts[part]["kits"]
	if not kits.has(key):
		kits[key] = MeshKit.new()
	return kits[key]

func _comp_part(comp: int) -> int:
	return int(comps[comp]["part"])

func _grow(comp: int, p: Vector3) -> void:
	var c: Dictionary = comps[comp]
	c["aabb_min"] = (c["aabb_min"] as Vector3).min(p)
	c["aabb_max"] = (c["aabb_max"] as Vector3).max(p)

func _grow_kit(comp: int, kit: MeshKit, from: int) -> void:
	for i in range(from, kit.verts.size(), 3):
		_grow(comp, kit.verts[i])

# ---------------------------------------------------------------- livery
func _lin(c: Color, a := 1.0) -> Color:
	var l := c.srgb_to_linear()
	l.a = a
	return l

func _paint_alpha() -> float:
	return 0.0 if mk == "metal" else 1.0

func _fus_param(z: float) -> Array:
	# Catmull-Rom interpolation of fuselage stations -> [hw, hh, yc, n]
	var st: Array = d["fuselage"]
	var n := st.size()
	if z <= float(st[0][0]):
		return [float(st[0][1]), float(st[0][2]), float(st[0][3]), float(st[0][4])]
	if z >= float(st[n - 1][0]):
		return [float(st[n - 1][1]), float(st[n - 1][2]), float(st[n - 1][3]), float(st[n - 1][4])]
	var k := 0
	while k < n - 2 and z > float(st[k + 1][0]):
		k += 1
	var z0 := float(st[k][0])
	var z1 := float(st[k + 1][0])
	var t := (z - z0) / maxf(z1 - z0, 1e-5)
	var out := []
	for comp in [1, 2, 3, 4]:
		var p0 := float(st[maxi(k - 1, 0)][comp])
		var p1 := float(st[k][comp])
		var p2 := float(st[k + 1][comp])
		var p3 := float(st[mini(k + 2, n - 1)][comp])
		var v := 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)
		if comp != 3:
			v = maxf(v, 0.0015)
		out.append(v)
	# monotone guard for tiny values
	return out

## zone: fus, wing, stab, fin, cowl, nacelle, spinner, blade, strut, gear, pant, frame
func paint(zone: String, p: Vector3, n: Vector3) -> Color:
	var base: Color = lv.get("base", Color.WHITE)
	var a1: Color = lv.get("a1", Color.RED)
	var a2: Color = lv.get("a2", Color.BLACK)
	var a3: Color = lv.get("a3", a2)
	var pa := _paint_alpha()
	var fp := _fus_param(clampf(p.z, 0.0, length))
	var yc: float = fp[2]
	var hh: float = fp[1]
	var rel_y := (p.y - yc) / maxf(hh, 0.001)   # -1 bottom .. 1 top
	var zf := p.z / length
	var bspan := _max_span() * 0.5
	var s := absf(p.x) / maxf(bspan, 0.01)
	var col := base
	var alpha := pa
	match zone:
		"blade":
			return _lin(Color(0.06, 0.06, 0.07))
		"strut", "gear":
			return _lin(Color(0.18, 0.18, 0.2) if mk != "metal" else Color(0.7, 0.72, 0.74), 1.0)
		"frame":
			return _lin(a2 if scheme != "p51" else Color(0.75, 0.77, 0.8), 1.0 if scheme != "p51" else 0.0)
	match scheme:
		"swoosh":
			if zone == "fus":
				var sw := 0.25 * sin(zf * 7.0 + 0.6) - 0.1
				if absf(rel_y - sw) < 0.16 and zf > 0.12 and zf < 0.9: col = a1
				elif rel_y < -0.55: col = a2.lerp(base, 0.7)
				if zf < 0.1: col = a2
			elif zone == "wing":
				if s > 0.84: col = a1
				elif _wing_chord_frac(p) < 0.1 and s > 0.3: col = a1.lerp(base, 0.35)
			elif zone == "fin":
				if p.y > 0.14 or (p.z - (float(d["vtails"][0]["z"]) + 0.02)) > (p.y - 0.06) * 1.6: col = a1
			elif zone == "stab":
				if s > 0.13 and absf(p.x) > 0.2: col = a1
			elif zone == "cowl" or zone == "spinner":
				col = a2 if zone == "cowl" else base
			elif zone == "pant":
				col = a1
		"cub":
			if zone == "fus":
				var zig := 0.12 * sin(zf * 30.0)
				if absf(rel_y - 0.15 - zig) < 0.11 and zf > 0.15 and zf < 0.95: col = a1
				if zf < 0.09: col = a1
			elif zone == "wing":
				if s > 0.92: col = a1
			elif zone == "fin" or zone == "stab":
				if zone == "fin" and p.y > 0.12: col = a1
			elif zone == "cowl":
				col = a1
			elif zone == "spinner":
				col = a1
		"stol":
			if zone == "fus":
				if rel_y < -0.1 + 0.3 * sin(zf * 4.0) and zf > 0.2: col = a1
				if absf(rel_y - 0.35 + zf * 0.4) < 0.07 and zf > 0.25 and zf < 0.85: col = a2
				if zf < 0.08: col = a1
			elif zone == "wing":
				if s > 0.82: col = a1
				elif s > 0.76: col = a2
			elif zone == "fin":
				if p.y > 0.13: col = a1
				elif p.y > 0.115: col = a2
			elif zone == "stab":
				if s > 0.14: col = a1
			elif zone == "cowl": col = a1
			elif zone == "spinner": col = a2
		"sunburst", "bipe":
			if zone == "wing":
				if n.y > 0.0:
					var w: Dictionary = _wing_ctx
					var cz := float(w.get("z", 0.4)) + float(w.get("root", 0.4))
					var ang := atan2(absf(p.x), cz - p.z)
					if int(floor(ang / 0.16)) % 2 == 0 and s > 0.12: col = a1
				elif s > 0.8: col = a1
			elif zone == "fus":
				if rel_y < 0.1: col = a1
				if absf(rel_y - 0.1) < 0.08: col = a2
				if zf < 0.12: col = a1
			elif zone == "fin" or zone == "stab":
				var band := int(floor((p.y if zone == "fin" else absf(p.x)) / 0.05)) % 2
				if band == 0: col = a1
			elif zone == "cowl": col = a1
			elif zone == "spinner": col = a1
			elif zone == "pant": col = a1
		"aerostar":
			if zone == "fus":
				if rel_y < -0.2: col = a1
				if absf(rel_y + 0.1 - 0.15 * sin(zf * 5.0)) < 0.07: col = a2
				if zf < 0.1: col = a1
			elif zone == "wing":
				if n.y < 0.0 and s > 0.2: col = a1
				if s > 0.9: col = a2
			elif zone == "fin":
				if p.y > 0.15: col = a1
			elif zone == "stab":
				if n.y < 0.0: col = a1
			elif zone == "cowl": col = a1
			elif zone == "spinner": col = a2
			elif zone == "pant": col = a1
		"p51":
			alpha = 0.0
			if zone == "fus":
				if zf < 0.12:
					col = a1; alpha = 1.0
				elif zf < 0.17:
					var ck := int(floor(p.z / 0.018)) + int(floor(atan2(p.y - yc, p.x) / 0.35))
					col = a2 if ck % 2 == 0 else a1
					alpha = 1.0
				elif rel_y > 0.55 and p.z < 0.52:
					col = a3; alpha = 1.0
				elif zf > 0.70 and zf < 0.80 and rel_y < 0.2:
					col = Color(0.05, 0.05, 0.05) if int(floor((p.z - length * 0.7) / (length * 0.02))) % 2 == 0 else Color(0.95, 0.95, 0.95)
					alpha = 1.0
			elif zone == "wing":
				if s > 0.3 and s < 0.52 and n.y < 0.3:
					col = Color(0.05, 0.05, 0.05) if int(floor((s - 0.3) / 0.044)) % 2 == 0 else Color(0.95, 0.95, 0.95)
					alpha = 1.0
			elif zone == "fin":
				if p.y > 0.2: col = a1; alpha = 1.0
			elif zone == "cowl":
				col = a1; alpha = 1.0
			elif zone == "spinner":
				col = a1 if p.z > 0.04 else a2; alpha = 1.0
		"valor":
			if zone == "fus":
				if absf(rel_y + 0.1) < 0.12 and zf > 0.1: col = a1
				if absf(rel_y + 0.3) < 0.05 and zf > 0.15: col = a2
			elif zone == "wing":
				if s > 0.85 or (s > 0.78 and s < 0.81): col = a1
			elif zone == "fin":
				if p.y > 0.16: col = a1
			elif zone == "cowl": col = a1
			elif zone == "spinner": col = a2
		"t28":
			if zone == "fus":
				if absf(rel_y) < 0.07 and zf > 0.15: col = a1
				if zf < 0.1: col = a2
			elif zone == "wing":
				if s > 0.9: col = a1
			elif zone == "fin":
				if p.y > 0.2 and p.y < 0.23: col = a1
			elif zone == "cowl": col = a1 if p.z < 0.1 else base
			elif zone == "spinner": col = a1
		"viper":
			if zone == "fus":
				var zz := zf * 10.0
				var chev := absf(fposmod(zz, 2.0) - 1.0) * 0.4
				if rel_y > 0.1 + chev and zf > 0.3: col = a1
				if rel_y > 0.55 and zf < 0.3: col = a2
				if zf < 0.03: col = a2
				if rel_y < -0.3 and zf > 0.45 and zf < 0.8 and absf(rel_y + 0.45 - chev * 0.5) < 0.08: col = a2
			elif zone == "wing":
				if s > 0.75: col = a1
				elif s > 0.55 and _wing_chord_frac(p) < 0.35: col = a2
			elif zone == "fin":
				col = a1
				if p.y > 0.12 and p.y < 0.2 and p.z > 1.1: col = a2
			elif zone == "stab":
				if s > 0.12: col = a1
		"grey2":
			var camo := sin(p.x * 9.0 + p.z * 4.0) + sin(p.z * 7.0 - p.y * 11.0)
			col = a1 if camo > 0.4 else base
			if zone == "fus" and rel_y > 0.4 and zf < 0.1: col = a2
			if zone == "fin" and p.y > 0.4: col = base
		"camo_grey":
			# flowing two-tone splinter camo: smooth sine-sum blotches with crisp edges
			var cm := sin(p.x * 7.0 + p.z * 5.0 + sin(p.z * 9.0) * 0.8) + sin(p.z * 6.5 - p.x * 4.0 + p.y * 8.0) + 0.6 * sin(p.x * 13.0 - p.z * 11.0)
			col = a1 if cm > 0.55 else (base.lerp(a1, 0.5) if cm > 0.1 else base)
			if zone == "fus" and zf < 0.06: col = a2
		"hog":
			var camo2 := sin(p.x * 6.0 + p.z * 3.0) + 0.7 * sin(p.z * 9.0 + p.y * 5.0)
			col = a1 if camo2 > 0.2 else base
			if zone == "fus" and zf < 0.14 and rel_y < 0.1 and rel_y > -0.75 and absf(p.x) > 0.01:
				# shark mouth: red mouth with white teeth band
				var mouth_top := -0.05 - (0.14 - zf) * 2.0
				var mouth_bot := -0.65 + (0.14 - zf) * 1.2
				if rel_y < mouth_top and rel_y > mouth_bot:
					col = a2
					var tooth := absf(fposmod(p.z * 70.0, 1.0) - 0.5) * 2.0
					if rel_y > mouth_top - 0.13 * tooth or rel_y < mouth_bot + 0.13 * tooth:
						col = Color(0.95, 0.95, 0.95)
				if zf < 0.12 and zf > 0.095 and rel_y > -0.1 and rel_y < 0.08 and absf(zf - 0.108) < 0.012:
					col = Color(0.05, 0.05, 0.05)
		"cargo":
			if zone == "fus":
				if zf < 0.045: col = a1
				if absf(rel_y + 0.05) < 0.03 and zf > 0.1 and zf < 0.8: col = a2
		"airliner":
			if zone == "fus":
				if rel_y < -0.25: col = Color(0.72, 0.74, 0.78)
				if absf(rel_y + 0.05) < 0.09 and zf > 0.06: col = a1
				if absf(rel_y + 0.18) < 0.03 and zf > 0.06: col = a2
				if zf < 0.03: col = Color(0.25, 0.26, 0.28)
			elif zone == "fin":
				col = a1
				var sw := sin(p.z * 22.0 + p.y * 9.0)
				if sw > 0.75: col = a2
			elif zone == "wing" or zone == "stab":
				col = Color(0.78, 0.8, 0.83)
			elif zone == "nacelle":
				col = base if p.z > 0.0 else base
		"sst":
			if zone == "fin":
				var yy := p.y - 0.07
				if p.z > 1.62 + yy * 1.5: col = a1
				elif p.z > 1.56 + yy * 1.5: col = a2
			elif zone == "fus":
				if absf(rel_y + 0.1) < 0.03 and zf > 0.2 and zf < 0.85: col = a1
				if zf < 0.012: col = Color(0.1, 0.1, 0.1)
		_:
			pass
	if zone == "nacelle" and scheme in ["cargo", "grey2", "hog", "camo_grey"]:
		col = base
	# Real white paint reflects ~80-85 %; pure 1.0 albedo clips in direct sun and flattens all form.
	var peak := maxf(col.r, maxf(col.g, col.b))
	if peak > 0.86:
		col = Color(col.r * 0.86 / peak, col.g * 0.86 / peak, col.b * 0.86 / peak, col.a)
	return _lin(col, alpha)

func _wing_chord_frac(p: Vector3) -> float:
	var w: Dictionary = _wing_ctx
	if w.is_empty():
		return 0.5
	var half := float(w["span"]) * 0.5
	var s := clampf(absf(p.x) / half, 0.0, 1.0)
	var c := lerpf(float(w["root"]), float(w["tip"]), s)
	var zle := float(w["z"]) + absf(p.x) * tan(deg_to_rad(float(w["sweep"])))
	return clampf((p.z - zle) / c, 0.0, 1.0)

func _pfn(zone: String) -> Callable:
	return func(p: Vector3, n: Vector3, aa := false) -> Color:
		return paint_aa(zone, p, n) if aa else paint(zone, p, n)

## Anti-aliased livery: 5 taps on the surface tangent plane, averaged in linear space, so a
## hard-edged stripe/camo boundary becomes a ~1 cm soft edge that the mesh refinement can resolve
## as a clean line instead of vertex-quantised stair steps.
func paint_aa(zone: String, p: Vector3, n: Vector3) -> Color:
	if zone == "blade" or zone == "strut" or zone == "gear" or zone == "frame":
		return paint(zone, p, n)
	var r := clampf(length * 0.0016, 0.0022, 0.0045)
	var t1 := n.cross(Vector3.UP)
	if t1.length_squared() < 1e-4:
		t1 = n.cross(Vector3.RIGHT)
	t1 = t1.normalized() * r
	var t2 := n.cross(t1).normalized() * r
	var c0 := paint(zone, p, n) * 2.0
	var c1 := paint(zone, p + t1, n)
	var c2 := paint(zone, p - t1, n)
	var c3 := paint(zone, p + t2, n)
	var c4 := paint(zone, p - t2, n)
	return (c0 + c1 + c2 + c3 + c4) / 6.0

# ---------------------------------------------------------------- fuselage
func _ring(z: float, segs: int, scale := 1.0) -> PackedVector3Array:
	var fp := _fus_param(z)
	var hw: float = fp[0] * scale
	var hh: float = fp[1] * scale
	var yc: float = fp[2]
	var ex: float = fp[3]
	var r := PackedVector3Array()
	for k in segs:
		var t := TAU * float(k) / segs - PI * 0.5
		var c := cos(t)
		var s := sin(t)
		var e := 2.0 / ex
		var x := signf(c) * pow(absf(c), e) * hw
		var y := signf(s) * pow(absf(s), e) * hh + yc
		r.append(Vector3(x, y, z))
	return r

func _build_fuselage() -> void:
	var st: Array = d["fuselage"]
	var z0 := float(st[0][0])
	var z1 := float(st[st.size() - 1][0])
	# Livery is painted per vertex, so a denser loft keeps stripes and camo edges crisp.
	var segs := 40 if lod_detail >= 2 else (24 if lod_detail >= 1 else 12)
	var nrows := 110 if lod_detail >= 2 else (44 if lod_detail >= 1 else 16)
	var core := int(cidx["fuselage"])
	var tail := _add_comp("tail_boom", core, "fuselage", 0.9, true)
	var nose := -1
	if z_nose > 0.0:
		nose = _add_comp("nose", core, "engine", 1.1)
	# row z positions (denser at ends)
	var zs := PackedFloat32Array()
	for i in nrows + 1:
		var t := float(i) / nrows
		var tt := 0.6 * t + 0.4 * (0.5 - 0.5 * cos(t * PI))
		var zz := lerpf(z0, z1, tt)
		if absf(zz - z_split) < 0.006 or (nose >= 0 and absf(zz - z_nose) < 0.006):
			continue
		zs.append(zz)
	zs.append(z_split)
	if nose >= 0:
		zs.append(z_nose)
	zs.sort()
	var groups := {core: [], tail: []}
	if nose >= 0:
		groups[nose] = []
	for z in zs:
		var ring := _ring(z, segs)
		var target := core
		if nose >= 0 and z <= z_nose + 1e-5:
			target = nose
		elif z >= z_split - 1e-5:
			target = tail
		(groups[target] as Array).append(ring)
		# boundary rings are shared
		if absf(z - z_split) < 1e-5:
			(groups[core] as Array).append(ring)
		if nose >= 0 and absf(z - z_nose) < 1e-5:
			(groups[core] as Array).append(ring)
	# sort core rows by z (boundary appended out of order)
	for key in groups.keys():
		var rows: Array = groups[key]
		rows.sort_custom(func(a, b): return (a as PackedVector3Array)[0].z < (b as PackedVector3Array)[0].z)
		if rows.size() >= 2:
			var kit := _kit(_comp_part(key), "body")
			var start := kit.verts.size()
			var zone := "cowl" if key == nose else "fus"
			# ordering: columns go -90deg -> around (bottom, right, top, left); rows +z
			# cross(dj, di): at right side dj=+y, di=+z -> +x outward. Good.
			kit.add_grid(rows, true, _pfn(zone))
			_grow_kit(key, kit, start)
	# end caps
	var first := _ring(z0, segs)
	var last := _ring(z1, segs)
	var cap_front_comp := nose if nose >= 0 else core
	var fp0 := _fus_param(z0)
	_kit(_comp_part(cap_front_comp), "body").add_cap(Vector3(0, fp0[2], z0), first, Vector3(0, 0, -1), _pfn("cowl" if nose >= 0 else "fus"))
	var fp1 := _fus_param(z1)
	var is_jet := String(d["engines"][0]["type"]) in ["edf", "turbine"] and float((d["engines"][0]["pos"] as Vector3).z) > length * 0.7 and absf((d["engines"][0]["pos"] as Vector3).x) < 0.08
	if not is_jet:
		_kit(_comp_part(tail), "body").add_cap(Vector3(0, fp1[2], z1), last, Vector3(0, 0, 1), _pfn("fus"))
	comps[core]["center"] = Vector3(0, 0, (z0 + z_split) * 0.5)
	if lod_detail >= 1:
		_fracture_pair(core, tail, _ring(z_split, segs, 0.99), Vector3.BACK)
		if nose >= 0: _fracture_pair(core, nose, _ring(z_nose, segs, 0.99), Vector3.FORWARD)

# ---------------------------------------------------------------- canopy & cockpit
func _build_canopy() -> void:
	var cd: Dictionary = d["canopy"]
	if cd.is_empty():
		return
	var core := int(cidx["fuselage"])
	var style := String(cd.get("style", "bubble"))
	var z0 := float(cd["z0"])
	var z1 := float(cd["z1"])
	var hw := float(cd["hw"])
	var hh := float(cd["hh"])
	var yb := float(cd["y"])
	var tint: Color = cd.get("tint", Color(0.1, 0.12, 0.15))
	var can := _add_comp("canopy", core, "canopy", 0.6)
	if style == "airliner":
		_build_airliner_windscreen(can, core, z0, z1)
		return
	var segs := 16
	var rows := []
	var n := 14
	for i in n + 1:
		var t := float(i) / n
		var z := lerpf(z0, z1, t)
		# profile: bubble = sin arch, jet = long pointed teardrop, cabin = boxy
		var prof := sin(t * PI)
		if style == "jet":
			prof = pow(sin(t * PI), 0.7) * (1.0 - 0.35 * t)
		elif style == "cabin":
			prof = clampf(sin(t * PI) * 1.8, 0.0, 1.0)
		elif style == "cockpit":
			prof = clampf(sin(t * PI) * 1.4, 0.0, 1.0)
		elif style == "open":
			prof = clampf(t * 3.0, 0.0, 1.0) * 0.5 * (1.0 if t < 0.35 else 0.0)
		prof = maxf(prof, 0.02)
		var ring := PackedVector3Array()
		var fp := _fus_param(z)
		var hwz: float = minf(hw, fp[0] * 1.02)
		for k in segs + 1:
			var a := PI * float(k) / segs  # 0..PI  right -> top -> left
			var x := cos(a) * hwz * (0.55 + 0.45 * prof)
			var y := yb + sin(a) * hh * prof
			ring.append(Vector3(x, y, z))
		rows.append(ring)
	if style == "open":
		# windscreen only
		var kit := _kit(_comp_part(can), "glass")
		var ws := Vector3(0, yb, z0)
		kit.add_quad(ws + Vector3(-hw * 0.8, 0, 0), ws + Vector3(hw * 0.8, 0, 0), ws + Vector3(hw * 0.6, hh * 0.9, 0.03), ws + Vector3(-hw * 0.6, hh * 0.9, 0.03), Color(1, 1, 1), false, Vector3(0, 0.3, -1))
	else:
		# grid: columns across (right->left over top), rows along z -> cross(dj, di): at top dj = -x, di = +z -> (-x) x z = +y. outward.
		var kit := _kit(_comp_part(can), "glass")
		var start := kit.verts.size()
		kit.add_grid(rows, false, MeshKit.const_color(Color.WHITE))
		_grow_kit(can, kit, start)
		# frame: bow at front and a mid hoop for bubble/jet
		var fk := _kit(_comp_part(can), "body")
		for hz in ([0.02, 0.5] if style != "cabin" else [0.02, 0.45, 0.98]):
			var ri := int(hz * n)
			var ring: PackedVector3Array = rows[ri]
			for k in segs:
				var a2: Vector3 = ring[k]
				var b2: Vector3 = ring[k + 1]
				fk.add_cylinder(a2, b2, 0.0022 * length, 0.0022 * length, 4, _pfn("frame"), false, true)
	# cockpit tub + pilot
	var ck := _kit(_comp_part(core), "cockpit")
	var zc := lerpf(z0, z1, 0.5 if style != "jet" else 0.55)
	var fpc := _fus_param(zc)
	var tub_top := yb + 0.004
	ck.add_ellipsoid(Vector3(0, tub_top - 0.002, zc), Vector3(minf(hw, fpc[0]) * 0.85, 0.008, (z1 - z0) * 0.42), 12, 6, MeshKit.const_color(Color(0.05, 0.05, 0.05)))
	if style in ["bubble", "jet", "open", "cabin"] and lod_detail >= 1:
		var ps := clampf(hw * 0.85, 0.02, 0.08)
		var pz := zc + (z1 - z0) * (0.08 if style != "cabin" else -0.05)
		var head_y := yb + ps * 0.95
		if style == "cabin":
			head_y = yb + ps * 0.55
		var pk := _kit(_comp_part(core), "plastic")
		var helmet := _lin(Color(0.92, 0.92, 0.9) if scheme != "p51" else Color(0.35, 0.25, 0.15))
		pk.add_ellipsoid(Vector3(0, head_y, pz), Vector3(ps * 0.42, ps * 0.46, ps * 0.44), 10, 6, MeshKit.const_color(helmet), Basis(), true)
		pk.add_ellipsoid(Vector3(0, head_y - ps * 0.02, pz - ps * 0.3), Vector3(ps * 0.3, ps * 0.2, ps * 0.14), 8, 4, MeshKit.const_color(_lin(Color(0.05, 0.05, 0.06))), Basis(), true)
		pk.add_ellipsoid(Vector3(0, head_y - ps * 0.75, pz + ps * 0.1), Vector3(ps * 0.6, ps * 0.42, ps * 0.4), 10, 6, MeshKit.const_color(_lin(Color(0.22, 0.28, 0.2))), Basis(), true)

## Flush airliner / transport flight-deck glazing: dark glass panes that wrap the nose crown 1.5 mm proud of the fuselage skin,
## separated by thin frame mullions, with an opaque dark backing so it reads as a windscreen rather than a hole.
func _build_airliner_windscreen(can: int, core: int, z0: float, z1: float) -> void:
	var nz := 10
	var na := 12
	var a0 := deg_to_rad(32.0)
	var a1 := deg_to_rad(148.0)
	var panes := 5
	var rows_back := []
	var rows_glass := []
	for i in nz + 1:
		var t := float(i) / nz
		# the aft edge is swept: the side panes end further aft than the centre ones
		var z := lerpf(z0, z1, t)
		var fp := _fus_param(z)
		var e := 2.0 / maxf(float(fp[3]), 1.0)
		var rb := PackedVector3Array()
		var rg := PackedVector3Array()
		for k in na + 1:
			var a := lerpf(a0, a1, float(k) / na)
			var c := cos(a)
			var sn := sin(a)
			var base := Vector3(signf(c) * pow(absf(c), e) * float(fp[0]), signf(sn) * pow(absf(sn), e) * float(fp[1]) + float(fp[2]), z)
			var nrm := Vector3(c / maxf(float(fp[0]), 0.01), sn / maxf(float(fp[1]), 0.01), 0.0).normalized()
			rb.append(base + nrm * 0.0008)
			rg.append(base + nrm * 0.0016 * length / 1.5 + nrm * 0.0006)
		rows_back.append(rb)
		rows_glass.append(rg)
	var bk := _kit(_comp_part(can), "cockpit")
	var st0 := bk.verts.size()
	bk.add_grid(rows_back, false, MeshKit.const_color(Color(0.015, 0.018, 0.022)))
	_grow_kit(can, bk, st0)
	var gk := _kit(_comp_part(can), "glass")
	var st1 := gk.verts.size()
	gk.add_grid(rows_glass, false, MeshKit.const_color(Color.WHITE))
	_grow_kit(can, gk, st1)
	# frame: arch round the front and rear edges plus mullions between the panes
	var fk := _kit(_comp_part(can), "body")
	var th := 0.0022 * length
	for ri in [0, nz]:
		var ring: PackedVector3Array = rows_glass[ri]
		for k in na:
			fk.add_cylinder(ring[k], ring[k + 1], th, th, 4, _pfn("frame"), false, true)
	for m in range(1, panes):
		var kk := int(round(float(m) / panes * na))
		for i in nz:
			fk.add_cylinder((rows_glass[i] as PackedVector3Array)[kk], (rows_glass[i + 1] as PackedVector3Array)[kk], th, th, 4, _pfn("frame"), false, true)
	# flight crew silhouettes behind the glass
	if lod_detail >= 1:
		var zc := lerpf(z0, z1, 0.55)
		var fpc := _fus_param(zc)
		var ps := clampf(float(fpc[0]) * 0.28, 0.012, 0.03)
		var pk := _kit(_comp_part(core), "plastic")
		for sx in [-1.0, 1.0]:
			pk.add_ellipsoid(Vector3(sx * float(fpc[0]) * 0.38, float(fpc[2]) + float(fpc[1]) * 0.52, zc), Vector3(ps * 0.42, ps * 0.46, ps * 0.44), 8, 5, MeshKit.const_color(_lin(Color(0.55, 0.45, 0.38))), Basis(), true)

# ---------------------------------------------------------------- lifting surfaces
## Generic lifting-surface description.
func _surf(root_pt: Vector3, span_dir: Vector3, thick_dir: Vector3, half_span: float, rc: float, tc: float,
		sweep_deg: float, t: float, camber: float, tw_r: float, tw_t: float) -> Dictionary:
	return {"root": root_pt, "span": span_dir.normalized(), "thick": thick_dir.normalized(), "chord": Vector3(0, 0, 1),
		"half": half_span, "rc": rc, "tc": tc, "tan_sw": tan(deg_to_rad(sweep_deg)), "t": t, "m": camber,
		"tw_r": deg_to_rad(tw_r), "tw_t": deg_to_rad(tw_t)}

func _airfoil(u: float, t: float, m: float) -> Vector2:
	# returns (yc, yt) as chord fractions (NACA 4-digit, p = 0.4)
	var yt := 5.0 * t * (0.2969 * sqrt(maxf(u, 0.0)) - 0.1260 * u - 0.3516 * u * u + 0.2843 * u * u * u - 0.1015 * u * u * u * u)
	var pc := 0.4
	var yc := 0.0
	if m > 0.0:
		if u < pc:
			yc = m / (pc * pc) * (2.0 * pc * u - u * u)
		else:
			yc = m / ((1.0 - pc) * (1.0 - pc)) * ((1.0 - 2.0 * pc) + 2.0 * pc * u - u * u)
	return Vector2(yc, maxf(yt, 0.0006))

func _sp(sf: Dictionary, s: float, u: float, upper: float) -> Vector3:
	var L := s * float(sf["half"])
	var c := lerpf(float(sf["rc"]), float(sf["tc"]), s)
	var zle := L * float(sf["tan_sw"])
	var af := _airfoil(u, float(sf["t"]), float(sf["m"]))
	var h := (af.x + upper * af.y) * c
	var a := (u - 0.25) * c
	var tw := lerpf(float(sf["tw_r"]), float(sf["tw_t"]), s)
	var h2 := h * cos(tw) - a * sin(tw)
	var a2 := a * cos(tw) + h * sin(tw)
	return (sf["root"] as Vector3) + (sf["span"] as Vector3) * L + (sf["chord"] as Vector3) * (zle + 0.25 * c + a2) + (sf["thick"] as Vector3) * h2

func _chord_samples(u0: float, u1: float, n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in n + 1:
		var t := float(i) / n
		var cu := 0.5 - 0.5 * cos(t * PI)
		out.append(lerpf(u0, u1, cu))
	return out

func _needs_flip(sf: Dictionary) -> bool:
	return (sf["span"] as Vector3).cross(sf["chord"] as Vector3).dot(sf["thick"] as Vector3) < 0.0

## Builds geometry for span range [s0,s1], chord range [u0,u1] into kit.
## kind "main" (LE included, closed with a cut face at u1), "ctrl" (hinge face at u0, TE at u1)
func _surface_piece(kit: MeshKit, sf: Dictionary, s0: float, s1: float, u0: float, u1: float, zone: String,
		cap0: bool, cap1: bool, tip_round := false) -> void:
	var nsp := maxi(2, int(ceil((s1 - s0) * float(sf["half"]) / (0.03 if lod_detail >= 2 else 0.05))) + 1)
	if lod_detail == 0:
		nsp = 2
	var ncs := 20 if lod_detail >= 2 else (10 if lod_detail >= 1 else 5)
	var flip := _needs_flip(sf)
	var col := _pfn(zone)
	var loops := []  # per span station: full loop points (for caps)
	var strips := {"a": [], "b": [], "c": []}
	for i in nsp:
		var s := lerpf(s0, s1, float(i) / (nsp - 1))
		if u0 <= 0.0001:
			# continuous upper (u1->0) + lower (0->u1)
			var row := PackedVector3Array()
			var us := _chord_samples(0.0, u1, ncs)
			for k in range(us.size() - 1, -1, -1):
				row.append(_sp(sf, s, us[k], 1.0))
			for k in range(1, us.size()):
				row.append(_sp(sf, s, us[k], -1.0))
			strips["a"].append(row)
			var cut := PackedVector3Array([_sp(sf, s, u1, -1.0), _sp(sf, s, u1, 1.0)])
			strips["b"].append(cut)
			loops.append(row)
		else:
			var us2 := _chord_samples(u0, u1, maxi(ncs / 2, 3))
			var up := PackedVector3Array()
			for k in range(us2.size() - 1, -1, -1):
				up.append(_sp(sf, s, us2[k], 1.0))
			var lo := PackedVector3Array()
			for k in us2.size():
				lo.append(_sp(sf, s, us2[k], -1.0))
			strips["a"].append(up)
			strips["b"].append(PackedVector3Array([_sp(sf, s, u0, 1.0), _sp(sf, s, u0, -1.0)]))
			strips["c"].append(lo)
			var loop := PackedVector3Array()
			loop.append_array(up)
			loop.append_array(lo)
			loops.append(loop)
	for key in ["a", "b", "c"]:
		var rows: Array = strips[key]
		if rows.size() >= 2:
			kit.add_grid(rows, false, col, true, flip)
	var sd: Vector3 = sf["span"]
	if cap0:
		var l0: PackedVector3Array = loops[0]
		kit.add_cap(_centroid(l0), l0, -sd, col)
	if cap1:
		var l1: PackedVector3Array = loops[loops.size() - 1]
		if tip_round and u0 <= 0.0001:
			_round_tip(kit, sf, s1, u1, col, flip)
		else:
			kit.add_cap(_centroid(l1), l1, sd, col)

func _round_tip(kit: MeshKit, sf: Dictionary, s: float, u1: float, col: Callable, flip: bool) -> void:
	# extrude the tip section outward while collapsing thickness -> rounded tip
	var c := lerpf(float(sf["rc"]), float(sf["tc"]), s)
	var ext := c * 0.18
	var rows := []
	var us := _chord_samples(0.0, u1, 10 if lod_detail >= 1 else 5)
	var sd: Vector3 = sf["span"]
	var th: Vector3 = sf["thick"]
	for i in 5:
		var a := float(i) / 4.0 * PI * 0.5
		var row := PackedVector3Array()
		var base_pts := []
		for k in range(us.size() - 1, -1, -1):
			base_pts.append([us[k], 1.0])
		for k in range(1, us.size()):
			base_pts.append([us[k], -1.0])
		# chord shrink toward mid-chord, thickness toward camber line
		for bp in base_pts:
			var pu := _sp(sf, s, bp[0], bp[1])
			var pc := _sp(sf, s, bp[0], 0.0)
			var mid := _sp(sf, s, 0.45, 0.0)
			var q: Vector3 = pc + (pu - pc) * cos(a)
			q = mid + (q - mid) * (1.0 - 0.35 * sin(a))
			q += sd * ext * sin(a)
			row.append(q)
		rows.append(row)
	kit.add_grid(rows, false, col, true, flip)
	var last: PackedVector3Array = rows[rows.size() - 1]
	kit.add_cap(_centroid(last), last, sd, col)

func _centroid(pts: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for p in pts:
		c += p
	return c / maxf(pts.size(), 1)

func _tau(cf: float) -> float:
	if cf >= 0.99:
		return 1.0
	var th := acos(clampf(2.0 * cf - 1.0, -1.0, 1.0))
	return clampf(1.0 - (th - sin(th)) / PI, 0.0, 1.0)

func _helmbold(ar: float) -> float:
	return TAU * ar / (2.0 + sqrt(ar * ar + 4.0))

## Adds a control surface (pivoted part) for span range [s0,s1], chord from hinge.
func _control_surface(comp: int, sf: Dictionary, s0: float, s1: float, hinge: float, zone: String, mix: Array, sid: String) -> int:
	var inset := 0.004 / maxf(float(sf["half"]), 0.05)
	var a0 := s0 + inset
	var a1 := s1 - inset
	var hp0 := _sp(sf, a0, hinge, 0.0)
	var hp1 := _sp(sf, a1, hinge, 0.0)
	var part := _new_part(comp, _comp_part(comp), hp0, sid)
	var kit := _kit(part, "body")
	var start := kit.verts.size()
	_surface_piece(kit, sf, a0, a1, hinge + 0.006, 1.0, zone, true, true)
	_grow_kit(comp, kit, start)
	# axis oriented so that +angle = trailing edge toward -thick ("down")
	var axis := (hp1 - hp0).normalized()
	var want := (sf["chord"] as Vector3).cross(sf["thick"] as Vector3) * -1.0  # = f x n with f=-chord
	if axis.dot(want) < 0.0:
		axis = -axis
	# control horn + pushrod detail (LOD0 only)
	if lod_detail >= 2:
		var hs := lerpf(a0, a1, 0.2)
		var hb := _sp(sf, hs, hinge + 0.03, -1.0)
		var c := lerpf(float(sf["rc"]), float(sf["tc"]), hs)
		var th: Vector3 = sf["thick"]
		var hk := _kit(part, "plastic")
		var horn_top := hb - th * c * 0.12
		hk.add_triangle(hb, hb + Vector3(0, 0, c * 0.06), horn_top, _lin(Color(0.95, 0.95, 0.95)), true, (sf["span"] as Vector3))
		hk.add_triangle(hb, horn_top, hb + Vector3(0, 0, c * 0.06), _lin(Color(0.95, 0.95, 0.95)), true, -(sf["span"] as Vector3))
		var mk2 := _kit(_comp_part(comp if not comps[comp].has("host") else int(comps[comp]["host"])), "metalbare")
		mk2.add_cylinder(horn_top + Vector3(0, 0, 0.002), horn_top + Vector3(0, 0, -c * 0.45) + th * c * 0.02, 0.0012, 0.0012, 4, MeshKit.const_color(_lin(Color(0.7, 0.7, 0.72), 0.0)), false, true)
	var sref := {"id": sid, "comp": comp, "mix": mix, "part": part, "axis": axis, "defl": 0.0, "cmd": 0.0}
	surfaces.append(sref)
	return surfaces.size() - 1

func _build_wing(w: Dictionary, wi: int) -> void:
	_wing_ctx = w
	var core := int(cidx["fuselage"])
	var half := float(w["span"]) * 0.5
	var x0 := float(w["x0"])
	var sw := float(w["sweep"])
	var dih := deg_to_rad(float(w["dihedral"]))
	var inc := float(w["incidence"])
	var wash := float(w["washout"])
	var rc := float(w["root"])
	var tc := float(w["tip"])
	var S := half * (rc + tc)          # total wing area (both sides)
	var ar := (2.0 * half) * (2.0 * half) / S
	var cla := _helmbold(ar)
	var split := 0.55
	var ail: Array = w["ail"]
	var flap: Array = w["flap"]
	var tip_style := String(w["tip_style"])
	var elevon := bool(w["elevon"])
	for side in [-1, 1]:
		var sname := "L" if side < 0 else "R"
		var span_dir := Vector3(side * cos(dih), sin(dih), 0.0)
		var thick_dir := Vector3(-side * sin(dih), cos(dih), 0.0)
		var root_pt := Vector3(0, float(w["y"]), float(w["z"]))
		var sf := _surf(root_pt, span_dir, thick_dir, half, rc, tc, sw, float(w["thick"]), float(w["camber"]), inc, inc - wash)
		var inner := _add_comp("wing%d_%s" % [wi, sname], core, "wing", 1.0)
		var tip := _add_comp("tip%d_%s" % [wi, sname], inner, "wingtip", 0.85)
		comps[inner]["center"] = _sp(sf, split * 0.5, 0.4, 0.0)
		comps[tip]["center"] = _sp(sf, (1.0 + split) * 0.5, 0.4, 0.0)
		comps[inner]["sf"] = sf
		comps[tip]["sf"] = sf
		comps[inner]["span_range"] = [0.0, split]
		comps[tip]["span_range"] = [split, 1.0]
		# chord ranges: build breakpoints
		var breaks := [x0 / half, split, 1.0]
		for rng in [ail, flap]:
			if rng.size() >= 2:
				breaks.append(float(rng[0]))
				breaks.append(float(rng[1]))
		breaks.sort()
		var uniq := []
		for b in breaks:
			if b >= x0 / half - 1e-4 and (uniq.is_empty() or absf(b - float(uniq[uniq.size() - 1])) > 1e-3):
				uniq.append(b)
		for k in range(uniq.size() - 1):
			var s0: float = uniq[k]
			var s1: float = uniq[k + 1]
			var mid := (s0 + s1) * 0.5
			var comp := inner if mid < split else tip
			var hinge := 1.0
			var ctrl_kind := ""
			if ail.size() >= 3 and mid > float(ail[0]) and mid < float(ail[1]):
				hinge = 1.0 - float(ail[2])
				ctrl_kind = "ail"
			elif flap.size() >= 3 and mid > float(flap[0]) and mid < float(flap[1]):
				hinge = 1.0 - float(flap[2])
				ctrl_kind = "flap"
			var kit := _kit(_comp_part(comp), "body")
			var start := kit.verts.size()
			var is_tip_end := absf(s1 - 1.0) < 1e-4
			_surface_piece(kit, sf, s0, s1, 0.0, hinge, "wing", k == 0, is_tip_end, is_tip_end and tip_style == "round")
			if hinge < 1.0 and is_tip_end == false:
				pass
			_grow_kit(comp, kit, start)
			if ctrl_kind != "":
				var mix := []
				if ctrl_kind == "ail":
					mix = [[CH_ROLL, float(-side)]]
					if elevon:
						mix.append([CH_PITCH, -1.0])
				else:
					mix = [[CH_FLAP, 1.0]]
				var ccomp := _add_comp("%s%d_%s_%d" % [ctrl_kind, wi, sname, k], comp, "control", 0.7)
				comps[ccomp]["host"] = comp
				comps[ccomp]["span_s"] = Vector2(s0, s1)
				comps[ccomp]["center"] = _sp(sf, mid, hinge + (1.0 - hinge) * 0.5, 0.0)
				_control_surface(ccomp, sf, s0, s1, hinge, "wing", mix, "%s%d_%s_%d" % [ctrl_kind, wi, sname, k])
			# slats
			if bool(w["slats"]) and mid > 0.12 and lod_detail >= 1:
				var sk := _kit(_comp_part(comp), "body")
				var sl := _surf(root_pt, span_dir, thick_dir, half, rc, tc, sw, 0.05, 0.08, inc + 12.0, inc - wash + 12.0)
				sl["root"] = root_pt + Vector3(0, 0.004, -rc * 0.1)
				var sl_s0 := maxf(s0, 0.12)
				var sl2 := sl.duplicate()
				sl2["rc"] = rc * 0.14
				sl2["tc"] = tc * 0.14
				_surface_piece(sk, sl2, sl_s0, minf(s1, 0.97), 0.0, 1.0, "wing", true, true)
		if lod_detail >= 1:
			var end_u := 1.0
			for control in [ail, flap]:
				if control.size() >= 3 and split >= float(control[0]) and split <= float(control[1]):
					end_u = minf(end_u, 1.0 - float(control[2]))
			var cut := PackedVector3Array()
			var samples := _chord_samples(0.0, end_u, 12)
			for j in range(samples.size() - 1, -1, -1): cut.append(_sp(sf, split, samples[j], 1.0))
			for j in range(1, samples.size()): cut.append(_sp(sf, split, samples[j], -1.0))
			_fracture_pair(inner, tip, cut, span_dir)
		# tip details
		var tipk := _kit(_comp_part(tip), "body")
		var tip_le := _sp(sf, 1.0, 0.0, 0.0)
		var tip_te := _sp(sf, 1.0, 1.0, 0.0)
		if tip_style == "winglet":
			var wl_root := _sp(sf, 0.99, 0.35, 0.0)
			var wsf := _surf(wl_root, Vector3(side * 0.25, 1, 0), Vector3(side, -0.25, 0), tc * 1.2, tc * 0.75, tc * 0.35, 40.0, 0.08, 0.0, 0, 0)
			_surface_piece(tipk, wsf, 0.0, 1.0, 0.0, 1.0, "wing", true, true)
		elif tip_style == "rail":
			tipk.add_cylinder(tip_le + Vector3(0, 0, -0.02), tip_te, 0.008, 0.008, 8, _pfn("wing"))
			if lod_detail >= 2:
				var mkit := _kit(_comp_part(tip), "plastic")
				mkit.add_cylinder(tip_le + Vector3(side * 0.012, 0, -0.06), tip_te + Vector3(side * 0.012, 0, 0.05), 0.007, 0.007, 8, MeshKit.const_color(_lin(Color(0.85, 0.85, 0.85))), true, true)
		elif tip_style == "droop":
			pass
		# navigation lights
		if lod_detail >= 1 and wi == 0:
			var lk := _kit(_comp_part(tip), "nav_" + ("red" if side < 0 else "green"))
			lk.add_ellipsoid(tip_le.lerp(tip_te, 0.3) + span_dir * 0.004, Vector3(0.006, 0.004, 0.012), 8, 4, MeshKit.const_color(Color.WHITE), Basis(), true)
		# struts (high wing)
		if bool(w["struts"]):
			var fz := float(w["z"]) + rc * 0.3
			var fp := _fus_param(fz + 0.05)
			var fus_low := Vector3(side * fp[0] * 0.95, fp[2] - fp[1] * 0.6, fz + 0.04)
			var wa := _sp(sf, 0.55, 0.2, -1.0)
			var wb := _sp(sf, 0.55, 0.62, -1.0)
			var stk := _kit(_comp_part(inner), "body")
			stk.add_cylinder(fus_low, wa, 0.0045, 0.0045, 6, _pfn("strut"))
			stk.add_cylinder(fus_low + Vector3(0, 0, 0.05), wb, 0.0045, 0.0045, 6, _pfn("strut"))
		# biplane rigging: cabane struts to the fuselage, interplane struts and flying wires.
		# Without these the upper wing simply floats above the fuselage.
		if wi == 1 and d["wings"].size() >= 2 and float(d["wings"][0]["y"]) > float(w["y"]) + 0.05 and cidx.has("wing0_%s" % sname):
			var uw: Dictionary = d["wings"][0]
			var usf: Dictionary = comps[int(cidx["wing0_%s" % sname])]["sf"]
			var uhalf := float(uw["span"]) * 0.5
			var s_l := 0.56
			var s_u := clampf(s_l * half / maxf(uhalf, 0.01), 0.05, 0.98)
			var rig := _kit(_comp_part(inner), "body")
			var wire_col := MeshKit.const_color(_lin(Color(0.12, 0.12, 0.13), 0.0))
			var sp_col := _pfn("strut")
			for u_pair in [[0.2, 0.22], [0.66, 0.68]]:
				var lo_pt := _sp(sf, s_l, float(u_pair[0]), 1.0)
				var up_pt := _sp(usf, s_u, float(u_pair[1]), -1.0)
				# slightly streamlined (flat-ish) strut: a main tube plus a thin fairing tube
				rig.add_cylinder(lo_pt, up_pt, 0.0048, 0.0048, 8, sp_col)
				rig.add_cylinder(lo_pt + Vector3(0, 0, 0.003), up_pt + Vector3(0, 0, 0.003), 0.0032, 0.0032, 6, sp_col, true, true)
			if lod_detail >= 2:
				# flying wires: X-bracing in the bay between the two struts
				var a0 := _sp(sf, s_l, 0.2, 1.0)
				var a1 := _sp(sf, s_l, 0.66, 1.0)
				var b0 := _sp(usf, s_u, 0.22, -1.0)
				var b1 := _sp(usf, s_u, 0.68, -1.0)
				rig.add_cylinder(a0, b1, 0.0011, 0.0011, 4, wire_col, true, true)
				rig.add_cylinder(a1, b0, 0.0011, 0.0011, 4, wire_col, true, true)
				# inboard landing/flying wire from the lower root to the upper strut foot
				var root_lo := _sp(sf, 0.04, 0.3, 1.0)
				rig.add_cylinder(root_lo, b0.lerp(b1, 0.5), 0.0011, 0.0011, 4, wire_col, true, true)
			# cabane: two struts per side from the upper wing centre section down to the fuselage decking
			var cab_kit := _kit(_comp_part(core), "body")
			var cz0 := float(uw["z"]) + float(uw["root"]) * 0.22
			var cz1 := float(uw["z"]) + float(uw["root"]) * 0.68
			for cz in [cz0, cz1]:
				var cfp := _fus_param(cz)
				var foot := Vector3(side * cfp[0] * 0.55, cfp[2] + cfp[1] * 0.92, cz)
				var head := Vector3(side * minf(uhalf * 0.1, 0.11), float(uw["y"]) - 0.012, cz)
				cab_kit.add_cylinder(foot, head, 0.0046, 0.0046, 6, sp_col)
		# aero panels: 4 per half wing
		var pbreaks := [0.0, 0.3, split, 0.8, 1.0]
		for k in range(pbreaks.size() - 1):
			var s0: float = pbreaks[k]
			var s1: float = pbreaks[k + 1]
			var mid := (s0 + s1) * 0.5
			var comp := inner if mid < split else tip
			var c0 := lerpf(rc, tc, s0)
			var c1 := lerpf(rc, tc, s1)
			var area := (s1 - s0) * half * (c0 + c1) * 0.5
			var cm := lerpf(rc, tc, mid)
			var tw := deg_to_rad(lerpf(inc, inc - wash, mid))
			var fwd := -Vector3(0, 0, 1) * cos(tw) + thick_dir * sin(tw)
			var nrm := thick_dir * cos(tw) + Vector3(0, 0, 1) * sin(tw)
			var pos := _sp(sf, mid, 0.25, 0.0)
			var ctrls := []
			# coverage by control ranges
			for rng_kind in ["ail", "flap"]:
				var rng: Array = ail if rng_kind == "ail" else flap
				if rng.size() < 3:
					continue
				var ov := maxf(0.0, minf(s1, float(rng[1])) - maxf(s0, float(rng[0])))
				if ov <= 0.0:
					continue
				var frac := ov / (s1 - s0)
				# find which control surfaces (segments) overlap
				for sref_i in surfaces.size():
					var sref: Dictionary = surfaces[sref_i]
					var sid := String(sref["id"])
					if not sid.begins_with("%s%d_%s_" % [rng_kind, wi, sname]):
						continue
					var cc: Dictionary = comps[int(sref["comp"])]
					var seg_mid := _span_of_surface(sf, cc)
					if seg_mid.x < s1 and seg_mid.y > s0:
						var ov2 := maxf(0.0, minf(s1, seg_mid.y) - maxf(s0, seg_mid.x)) / (s1 - s0)
						ctrls.append({"surf": sref_i, "frac": ov2, "cf": float(rng[2]), "tau": _tau(float(rng[2]))})
			var alpha0 := -float(w["camber"]) * 100.0 * 1.05
			var stall := float(w["stall_deg"]) + (6.0 if bool(w["slats"]) else 0.0)
			# wing/fuselage interference acts like extra dihedral (high wing) or less (low wing)
			var fpw := _fus_param(float(w["z"]) + rc * 0.3)
			var rel_h := (float(w["y"]) - float(fpw[2])) / maxf(float(fpw[1]), 0.01)
			var extra := clampf(rel_h, -1.0, 1.0) * deg_to_rad(2.5)
			var nrm2 := nrm.rotated(Vector3(0, 0, 1), -side * extra)
			var pn := _panel(pos, fwd, nrm2, area, ar, cm, cla, alpha0, stall, 0.009, comp, ctrls, "wing", sf, mid)
			pn["cm0"] = -2.3 * float(w["camber"])
			panels.append(pn)

func _span_of_surface(sf: Dictionary, cc: Dictionary) -> Vector2:
	# control comp centre -> span fraction; we store explicit range
	if cc.has("span_s"):
		return cc["span_s"]
	return Vector2(0, 1)

func _panel(pos: Vector3, fwd: Vector3, nrm: Vector3, area: float, ar: float, chord: float, cla: float,
		alpha0_deg: float, stall_deg: float, cd0: float, comp: int, ctrls: Array, role: String, sf := {}, s_mid := 0.5) -> Dictionary:
	return {"pos": pos, "fwd": fwd.normalized(), "nrm": nrm.normalized(), "span": fwd.normalized().cross(nrm.normalized()).normalized(),
		"area": area, "area0": area, "ar": ar, "chord": chord, "cla": cla, "a0": deg_to_rad(alpha0_deg),
		"stall": deg_to_rad(stall_deg), "cd0": cd0, "comp": comp, "ctrls": ctrls, "role": role,
		"wash": [], "eff": 1.0, "alive": true, "s_mid": s_mid, "cl": 0.0}

func _build_htail(h: Dictionary) -> void:
	var tail := int(cidx["tail_boom"])
	var half := float(h["span"]) * 0.5
	var rc := float(h["root"])
	var tc := float(h["tip"])
	var S := half * (rc + tc)
	var ar := (2.0 * half) * (2.0 * half) / S
	var cla := _helmbold(ar)
	var dih := deg_to_rad(float(h["dihedral"]))
	var stab := bool(h["stabilator"])
	var ecf := float(h["elev_cf"])
	var inc := float(h.get("incidence", 0.0))
	for side in [-1, 1]:
		var sname := "L" if side < 0 else "R"
		var span_dir := Vector3(side * cos(dih), sin(dih), 0)
		var thick_dir := Vector3(-side * sin(dih), cos(dih), 0)
		var sf := _surf(Vector3(0, float(h["y"]), float(h["z"])), span_dir, thick_dir, half, rc, tc, float(h["sweep"]), float(h["thick"]), 0.0, inc, inc)
		var sc := _add_comp("stab_" + sname, tail, "stab", 0.8)
		comps[sc]["center"] = _sp(sf, 0.5, 0.4, 0.0)
		comps[sc]["sf"] = sf
		var mix := [[CH_PITCH, -1.0]]
		if float(h["taileron"]) > 0.0:
			mix.append([CH_ROLL, -side * float(h["taileron"])])
		var ctrls := []
		var s_root := 0.12 if not stab else 0.0
		if stab:
			# whole surface pivots about ~30% root chord
			var ctrl_c := _add_comp("elev_" + sname, sc, "control", 0.7)
			comps[ctrl_c]["center"] = comps[sc]["center"]
			comps[ctrl_c]["span_s"] = Vector2(0, 1)
			var hp0 := _sp(sf, 0.0, 0.3, 0.0)
			var hp1 := _sp(sf, 1.0, 0.3, 0.0)
			var part := _new_part(ctrl_c, _comp_part(ctrl_c), hp0, "stabilator")
			var kit := _kit(part, "body")
			var start := kit.verts.size()
			_surface_piece(kit, sf, 0.02, 1.0, 0.0, 1.0, "stab", true, true)
			_grow_kit(ctrl_c, kit, start)
			var axis := (hp1 - hp0).normalized()
			var want := -(sf["chord"] as Vector3).cross(sf["thick"] as Vector3)
			if axis.dot(want) < 0.0:
				axis = -axis
			surfaces.append({"id": "elev_" + sname, "comp": ctrl_c, "mix": mix, "part": part, "axis": axis, "defl": 0.0, "cmd": 0.0})
			ctrls.append({"surf": surfaces.size() - 1, "frac": 1.0, "cf": 1.0, "tau": 1.0})
			# small fixed fairing stub
			_surface_piece(_kit(_comp_part(sc), "body"), sf, 0.0, 0.02, 0.0, 1.0, "stab", true, true)
		else:
			var kit2 := _kit(_comp_part(sc), "body")
			var st2 := kit2.verts.size()
			_surface_piece(kit2, sf, 0.0, 1.0, 0.0, 1.0 - ecf, "stab", true, true, true)
			_surface_piece(kit2, sf, 0.0, s_root, 1.0 - ecf, 1.0, "stab", false, true)
			_grow_kit(sc, kit2, st2)
			var ec := _add_comp("elev_" + sname, sc, "control", 0.7)
			comps[ec]["center"] = _sp(sf, 0.55, 1.0 - ecf * 0.5, 0.0)
			comps[ec]["span_s"] = Vector2(s_root, 1.0)
			var si := _control_surface(ec, sf, s_root, 1.0, 1.0 - ecf, "stab", mix, "elev_" + sname)
			ctrls.append({"surf": si, "frac": 1.0 - s_root, "cf": ecf, "tau": _tau(ecf)})
		var pos := _sp(sf, 0.45, 0.25, 0.0)
		var fwd := Vector3(0, 0, -1).rotated(span_dir, 0.0)
		var tw := deg_to_rad(inc)
		fwd = -Vector3(0, 0, 1) * cos(tw) + thick_dir * sin(tw)
		var nrm := thick_dir * cos(tw) + Vector3(0, 0, 1) * sin(tw)
		panels.append(_panel(pos, fwd, nrm, S * 0.5, ar, (rc + tc) * 0.5, cla, 0.0, 16.0 if not stab else 20.0, 0.01, sc, ctrls, "htail", sf, 0.45))

func _build_vtail(v: Dictionary, vi: int) -> void:
	var tail := int(cidx["tail_boom"])
	var sides := [0]
	if bool(v["mirror"]):
		sides = [-1, 1]
	for side in sides:
		var cant: float = deg_to_rad(float(v["cant"])) * (side if side != 0 else 1)
		var x: float = float(v["x"]) * (side if side != 0 else 1)
		var span_dir := Vector3(sin(cant), cos(cant), 0)
		var thick_dir := Vector3(cos(cant), -sin(cant), 0)   # normal points right (+x) for uncanted fin
		var rc := float(v["root"])
		var tc := float(v["tip"])
		var hgt := float(v["height"])
		var sf := _surf(Vector3(x, float(v["y"]), float(v["z"])), span_dir, thick_dir, hgt, rc, tc, float(v["sweep"]), float(v["thick"]), 0.0, 0.0, 0.0)
		var nm := "fin%d%s" % [vi, ("" if side == 0 else ("L" if side < 0 else "R"))]
		var parent := tail
		# fins mounted on the stab tips (A-10 style) hang off the stabilizer
		if absf(x) > 0.2 and cidx.has("stab_" + ("L" if side < 0 else "R")):
			parent = int(cidx["stab_" + ("L" if side < 0 else "R")])
		var fc := _add_comp(nm, parent, "fin", 0.8)
		comps[fc]["center"] = _sp(sf, 0.45, 0.4, 0.0)
		comps[fc]["sf"] = sf
		var rcf := float(v["rudder_cf"])
		var kit := _kit(_comp_part(fc), "body")
		var st := kit.verts.size()
		var r_s0 := 0.08
		_surface_piece(kit, sf, 0.0, 1.0, 0.0, 1.0 - rcf, "fin", true, true, true)
		_surface_piece(kit, sf, 0.0, r_s0, 1.0 - rcf, 1.0, "fin", false, true)
		if absf(x) > 0.2:
			# bottom half of end-plate fin
			var sf2 := _surf(Vector3(x, float(v["y"]), float(v["z"])), -span_dir, -thick_dir, hgt * 0.45, rc, rc * 0.75, float(v["sweep"]) * 0.4, float(v["thick"]), 0.0, 0.0, 0.0)
			_surface_piece(kit, sf2, 0.0, 1.0, 0.0, 1.0, "fin", false, true, true)
		_grow_kit(fc, kit, st)
		var rcomp := _add_comp("rudder%d%s" % [vi, ("" if side == 0 else ("L" if side < 0 else "R"))], fc, "control", 0.7)
		comps[rcomp]["center"] = _sp(sf, 0.55, 1.0 - rcf * 0.5, 0.0)
		comps[rcomp]["span_s"] = Vector2(r_s0, 1.0)
		# yaw right -> TE right(+x) -> force toward -x on tail. with normal +x, positive defl = TE toward -x.
		var si := _control_surface(rcomp, sf, r_s0, 1.0, 1.0 - rcf, "fin", [[CH_YAW, -1.0]], "rud%d_%d" % [vi, side])
		var S := hgt * (rc + tc) * 0.5
		var ar := 2.0 * hgt * hgt / S  # end-plate effect of fuselage/stab
		var pos := _sp(sf, 0.4, 0.25, 0.0)
		panels.append(_panel(pos, Vector3(0, 0, -1), thick_dir, S, ar, (rc + tc) * 0.5, _helmbold(ar), 0.0, 18.0, 0.01, fc,
			[{"surf": si, "frac": 1.0 - r_s0, "cf": rcf, "tau": _tau(rcf)}], "vtail", sf, 0.4))

# ---------------------------------------------------------------- helpers for tubes
func _grid_auto(kit: MeshKit, rows: Array, closed: bool, col: Callable, lod := true) -> void:
	# pick normal orientation so normals point away from each row's centroid
	var r0: PackedVector3Array = rows[rows.size() / 2]
	var c := _centroid(r0)
	var j := 0
	var jp := 1 % r0.size()
	var jm := (r0.size() - 1) if closed else 0
	var i1: PackedVector3Array = rows[mini(rows.size() / 2 + 1, rows.size() - 1)]
	var i0: PackedVector3Array = rows[maxi(rows.size() / 2 - 1, 0)]
	var n := (r0[jp] - r0[jm]).cross(i1[j] - i0[j])
	var flip := n.dot(r0[j] - c) < 0.0
	kit.add_grid(rows, closed, col, lod, flip)

func _find_wing_comp(x: float, wi := 0) -> int:
	var sname := "L" if x < 0.0 else "R"
	if not cidx.has("wing%d_%s" % [wi, sname]):
		return int(cidx["fuselage"])
	var half := float(d["wings"][wi]["span"]) * 0.5
	if absf(x) / half > 0.55 and cidx.has("tip%d_%s" % [wi, sname]):
		return int(cidx["tip%d_%s" % [wi, sname]])
	return int(cidx["wing%d_%s" % [wi, sname]])

func _prop_choice(e: Dictionary) -> Dictionary:
	var props: Array = d["props"]
	if props.is_empty():
		# derive a sensible prop from engine size
		var dia := 0.25
		if e.has("nacelle") and not (e["nacelle"] as Dictionary).is_empty():
			dia = 0.23
		return {"name": "stock", "d": dia, "pitch": dia * 0.6, "blades": 2}
	var i := clampi(int(cfg.get("prop", 0)), 0, props.size() - 1)
	return props[i]

# ---------------------------------------------------------------- engines
func _build_engine(e: Dictionary, ei: int) -> void:
	var t := String(e["type"])
	var pos: Vector3 = e["pos"]
	var dir: Vector3 = e["dir"]
	var core := int(cidx["fuselage"])
	var nac: Dictionary = e.get("nacelle", {})
	var ecomp := core
	var is_prop := t in ["electric", "glow2", "glow4", "gas2"]
	if not nac.is_empty():
		var host := _find_wing_comp(pos.x) if absf(pos.x) > 0.12 else (int(cidx["tail_boom"]) if pos.z > z_split else core)
		ecomp = _add_comp("nacelle%d" % ei, host, "nacelle", 1.0)
		comps[ecomp]["center"] = pos + Vector3(0, 0, float(nac["len"]) * 0.45)
		_build_nacelle(ecomp, e, nac, is_prop)
	elif is_prop and cidx.has("nose") and pos.z < length * 0.25:
		ecomp = int(cidx["nose"])
		comps[ecomp]["center"] = pos + Vector3(0, 0, 0.04)
	elif pos.z > z_split:
		ecomp = int(cidx["tail_boom"])
	var eng := {"def": e, "type": t, "pos": pos, "dir": dir, "comp": ecomp, "prop_comp": -1, "rot_part": -1,
		"disc_part": -1, "spin": int(e.get("spin", 1)), "D": 0.0, "pitch": 0.0, "blades": 2}
	if is_prop:
		var pr := _prop_choice(e)
		eng["D"] = float(pr["d"])
		eng["pitch"] = float(pr["pitch"])
		eng["blades"] = int(pr["blades"])
		var pc := _add_comp("prop%d" % ei, ecomp, "prop", 0.5)
		comps[pc]["center"] = pos
		eng["prop_comp"] = pc
		_build_prop(pc, e, eng)
		if ecomp == int(cidx.get("nose", -99)):
			_build_nose_engine_details(ecomp, e)
	else:
		_build_fan(ecomp, e, eng, ei)
	engines.append(eng)

func _build_prop(pc: int, e: Dictionary, eng: Dictionary) -> void:
	var pos: Vector3 = e["pos"]
	var sl := float(e.get("spinner_len", 0.06))
	var sr := float(e.get("spinner_r", 0.03))
	var R := float(eng["D"]) * 0.5
	var B := int(eng["blades"])
	var spin := int(eng["spin"])
	var hub := pos + Vector3(0, 0, -sl * 0.45)
	var rot := _new_part(pc, _comp_part(pc), hub, "prop_rot")
	eng["rot_part"] = rot
	# spinner (tip at pos.z - sl .. base at pos.z)
	var prof := []
	var n := 8
	for i in n + 1:
		var tt := float(i) / n
		prof.append(Vector2(tt * sl, sr * pow(sin(tt * PI * 0.5), 0.75)))
	var sk := _kit(rot, "body")
	sk.add_lathe(prof, pos + Vector3(0, 0, -sl), Basis(), 16 if lod_detail >= 1 else 8, _pfn("spinner"))
	# blades
	var bk := _kit(rot, "plastic")
	var tipc := Color(0.95, 0.95, 0.95) if scheme in ["p51", "cargo", "t28", "hog"] else Color(0.06, 0.06, 0.07)
	if scheme == "p51":
		tipc = lv.get("a2", Color.YELLOW)
	var nst := 7 if lod_detail >= 1 else 3
	for b in B:
		var psi := TAU * float(b) / B + 0.3
		var rdir := Vector3(cos(psi), sin(psi), 0)
		var tang := Vector3(sin(psi), -cos(psi), 0) * spin
		var rows := []
		for i in nst + 1:
			var tt := float(i) / nst
			var r := lerpf(sr * 0.75, R, tt)
			var chord := R * 2.0 * lerpf(0.075, 0.05, tt) * (1.0 + 0.4 * sin(tt * PI * 0.8))
			if tt > 0.9:
				chord *= 1.0 - (tt - 0.9) * 5.0
			var beta := atan2(float(eng["pitch"]), TAU * maxf(r, 0.01))
			var cdir := -tang * cos(beta) + Vector3(0, 0, 1) * sin(beta)   # LE -> TE
			var ndir := cdir.cross(rdir).normalized()
			var th := chord * lerpf(0.16, 0.07, tt)
			var ring := PackedVector3Array()
			for k in 8:
				var a := TAU * float(k) / 8.0
				var cx := cos(a) * 0.5 * chord
				var cy := sin(a) * 0.5 * th * (1.0 + 0.3 * cos(a))
				ring.append(hub + rdir * r + cdir * cx + ndir * cy)
			rows.append(ring)
		var ci := func(p: Vector3, _n: Vector3) -> Color:
			var rr := (Vector2(p.x - hub.x, p.y - hub.y)).length()
			return _lin(tipc if rr > R * 0.9 else Color(0.06, 0.06, 0.07))
		_grid_auto(bk, rows, true, ci)
		var lastr: PackedVector3Array = rows[rows.size() - 1]
		bk.add_cap(_centroid(lastr), lastr, rdir, ci)
	# motion-blur disc (non-rotating, sits in the prop comp)
	var dp := _new_part(pc, _comp_part(pc), hub, "prop_disc")
	eng["disc_part"] = dp
	var dk := _kit(dp, "disc")
	var segs := 32
	var rin := sr * 0.9
	for k in segs:
		var a0 := TAU * float(k) / segs
		var a1 := TAU * float(k + 1) / segs
		var p0 := hub + Vector3(cos(a0), sin(a0), 0) * rin
		var p1 := hub + Vector3(cos(a1), sin(a1), 0) * rin
		var p2 := hub + Vector3(cos(a1), sin(a1), 0) * R
		var p3 := hub + Vector3(cos(a0), sin(a0), 0) * R
		var i0 := dk.verts.size()
		for q in [[p0, Vector2(0, float(k) / segs)], [p1, Vector2(0, float(k + 1) / segs)], [p2, Vector2(1, float(k + 1) / segs)], [p3, Vector2(1, float(k) / segs)]]:
			dk.verts.append(q[0]); dk.norms.append(Vector3(0, 0, -1)); dk.cols.append(Color.WHITE); dk.uvs.append(q[1])
		for l in [dk.idx, dk.lod1, dk.lod2]:
			l.append_array(PackedInt32Array([i0, i0 + 2, i0 + 1, i0, i0 + 3, i0 + 2]))
	eng["disc_color"] = tipc

func _build_nose_engine_details(nc: int, e: Dictionary) -> void:
	if lod_detail < 1:
		return
	var t := String(e["type"])
	var pos: Vector3 = e["pos"]
	var fp := _fus_param(pos.z + 0.03)
	var k := _kit(_comp_part(nc), "metalbare")
	var grey := MeshKit.const_color(_lin(Color(0.26, 0.27, 0.29), 0.0))
	var dark := _kit(_comp_part(nc), "cockpit")
	if bool(e.get("radial", false)):
		# dark cowl opening with radial cylinder heads
		var fz := float(d["fuselage"][0][0]) + 0.002
		var fr: float = _fus_param(fz)[0]
		var ring := PackedVector3Array()
		for i in 20:
			var a := TAU * i / 20.0
			ring.append(Vector3(cos(a) * fr * 0.8, sin(a) * fr * 0.8 + float(_fus_param(fz)[2]), fz - 0.0005))
		dark.add_cap(Vector3(0, _fus_param(fz)[2], fz - 0.0005), ring, Vector3(0, 0, -1), MeshKit.const_color(Color(0.02, 0.02, 0.02)))
		for i in 9:
			var a := TAU * i / 9.0
			var dirr := Vector3(cos(a), sin(a), 0)
			k.add_cylinder(Vector3(0, float(_fus_param(fz)[2]), fz + 0.006) + dirr * fr * 0.25, Vector3(0, float(_fus_param(fz)[2]), fz + 0.006) + dirr * fr * 0.72, fr * 0.09, fr * 0.07, 6, grey, true, true)
		return
	if t == "glow2" or t == "gas2":
		# side-mounted cylinder head poking out of the cowl + muffler
		var hx: float = fp[0] * 0.9
		var hc := Vector3(hx, fp[2] + fp[1] * 0.1, pos.z + 0.035)
		var hr := 0.012 * float(e.get("qmax", 1.0)) ** 0.33 + 0.01
		k.add_cylinder(hc, hc + Vector3(hr * 2.2, 0, 0), hr, hr * 0.9, 10, grey, true, true)
		for f in 4:
			var fx := hc + Vector3(hr * (0.5 + f * 0.4), 0, 0)
			k.add_cylinder(fx, fx + Vector3(0.0015, 0, 0), hr * 1.35, hr * 1.35, 10, grey, true, true)
		k.add_cylinder(Vector3(hx * 0.9, fp[2] - fp[1] * 0.6, pos.z + 0.03), Vector3(hx * 0.9, fp[2] - fp[1] * 0.7, pos.z + 0.03 + length * 0.09), hr * 0.9, hr * 0.9, 10, grey, true, true)
	elif t == "glow4":
		var hc2 := Vector3(0, fp[2] + fp[1] * 0.95, pos.z + 0.04)
		var hr2 := 0.014 * float(e.get("qmax", 1.0)) ** 0.33
		k.add_cylinder(hc2, hc2 + Vector3(0, hr2 * 1.6, 0), hr2, hr2 * 0.85, 10, grey, true, true)
		var box := Transform3D(Basis().scaled(Vector3(hr2 * 1.9, hr2 * 0.7, hr2 * 1.3)), hc2 + Vector3(0, hr2 * 1.8, 0))
		k.add_box(box, _lin(Color(0.25, 0.25, 0.27), 0.0), true)
	# exhaust stacks for scale warbird
	var ns := int((d["details"] as Dictionary).get("exhaust_stacks", 0))
	for side in [-1, 1]:
		for i in ns:
			var ez := pos.z + 0.07 + i * 0.022
			var efp := _fus_param(ez)
			var ep := Vector3(side * efp[0] * 0.98, efp[2] + efp[1] * 0.2, ez)
			k.add_cylinder(ep, ep + Vector3(side * 0.012, -0.002, 0.004), 0.004, 0.0045, 6, MeshKit.const_color(_lin(Color(0.2, 0.15, 0.12), 0.0)), true, true)

func _build_nacelle(nc: int, e: Dictionary, nac: Dictionary, is_prop: bool) -> void:
	var pos: Vector3 = e["pos"]
	var L := float(nac["len"])
	var r := float(nac["r"])
	var kit := _kit(_comp_part(nc), "body")
	var start := kit.verts.size()
	if bool(nac.get("box", false)):
		# rounded-rectangle (superellipse) loft with a gentle exhaust taper instead of a raw box
		var rows := []
		var nst := 14 if lod_detail >= 1 else 5
		for si in nst + 1:
			var tt := float(si) / nst
			var zz := pos.z - 0.02 + (L + 0.02) * tt
			var taper := 1.0 - 0.14 * tt * tt
			var swell := 1.0 + 0.04 * sin(tt * PI)
			var ring := PackedVector3Array()
			for k in 24:
				var a := TAU * float(k) / 24.0 - PI * 0.5
				var ca := cos(a)
				var sa := sin(a)
				ring.append(Vector3(signf(ca) * pow(absf(ca), 0.5) * r * 1.05 * taper * swell, signf(sa) * pow(absf(sa), 0.5) * r * 0.95 * taper * swell, zz) + Vector3(pos.x, pos.y, 0.0))
			rows.append(ring)
		_grid_auto(kit, rows, true, _pfn("nacelle"))
		var dk := _kit(_comp_part(nc), "cockpit")
		dk.add_box(Transform3D(Basis().scaled(Vector3(r * 1.8, r * 1.6, 0.004)), pos + Vector3(0, 0, -0.022)), Color(0.02, 0.02, 0.02))
		dk.add_box(Transform3D(Basis().scaled(Vector3(r * 1.7, r * 1.5, 0.004)), pos + Vector3(0, 0, L - 0.018)), Color(0.02, 0.02, 0.02))
	else:
		var prof := []
		if is_prop:
			prof = [Vector2(0.0, r * 0.62), Vector2(L * 0.05, r * 0.9), Vector2(L * 0.2, r), Vector2(L * 0.6, r * 0.92), Vector2(L * 0.9, r * 0.55), Vector2(L, r * 0.2)]
		else:
			# rounded inlet lip, full barrel, tapered exhaust cone (instead of a flat-cut tube)
			prof = [Vector2(0.0, r * 0.80), Vector2(L * 0.012, r * 0.93), Vector2(L * 0.04, r * 1.02), Vector2(L * 0.12, r * 1.06),
				Vector2(L * 0.45, r * 1.04), Vector2(L * 0.78, r * 0.9), Vector2(L * 0.93, r * 0.74), Vector2(L, r * 0.64)]
		kit.add_lathe(prof, pos, Basis(), 18 if lod_detail >= 1 else 8, _pfn("nacelle"))
		if not is_prop:
			# intake face + exhaust
			var dk2 := _kit(_comp_part(nc), "cockpit")
			var ring := PackedVector3Array()
			var ring2 := PackedVector3Array()
			for i in 16:
				var a := TAU * i / 16.0
				ring.append(pos + Vector3(cos(a), sin(a), 0) * r * 0.86 + Vector3(0, 0, 0.012))
				ring2.append(pos + Vector3(cos(a), sin(a), 0) * r * 0.6 + Vector3(0, 0, L - 0.004))
			dk2.add_cap(pos + Vector3(0, 0, 0.012), ring, Vector3(0, 0, -1), MeshKit.const_color(Color(0.03, 0.03, 0.035)))
			dk2.add_cap(pos + Vector3(0, 0, L - 0.004), ring2, Vector3(0, 0, 1), MeshKit.const_color(Color(0.02, 0.02, 0.02)))
			# inner lip (dark tube)
			dk2.add_cylinder(pos + Vector3(0, 0, -0.001), pos + Vector3(0, 0, 0.012), r * 0.9, r * 0.86, 16, MeshKit.const_color(Color(0.05, 0.05, 0.05)), false)
	if bool(nac.get("pylon", false)):
		var wing_y := float(d["wings"][0]["y"]) + absf(pos.x) * tan(deg_to_rad(float(d["wings"][0]["dihedral"])))
		var top := pos + Vector3(0, r * 0.8, L * 0.35)
		var h := wing_y - top.y
		# swept, lens-section pylon lofted from the nacelle up into the wing
		var prows := []
		var chord_lo := L * 0.55
		var chord_hi := L * 0.9
		for pi in 6:
			var tt := float(pi) / 5.0
			var yy := lerpf(top.y - r * 0.4, top.y + h + 0.004, tt)
			var cc := lerpf(chord_lo, chord_hi, tt)
			var zle := pos.z + L * 0.12 - 0.06 * tt
			var th := lerpf(0.011, 0.008, tt)
			var pring := PackedVector3Array()
			for k in 12:
				var a := TAU * float(k) / 12.0
				pring.append(Vector3(pos.x + th * sin(a) * 0.5, yy, zle + cc * (0.5 - 0.5 * cos(a))))
			prows.append(pring)
		_grid_auto(kit, prows, true, _pfn("nacelle"))
	_grow_kit(nc, kit, start)

func _build_fan(ec: int, e: Dictionary, eng: Dictionary, ei: int) -> void:
	var pos: Vector3 = e["pos"]
	var t := String(e["type"])
	var fd := float(e.get("fan_d", 0.07))
	var intake := String(e.get("intake", "nose"))
	var nac: Dictionary = e.get("nacelle", {})
	var core := int(cidx["fuselage"])
	eng["D"] = fd
	var fan_center := pos
	if not nac.is_empty():
		fan_center = pos + Vector3(0, 0, 0.018)
		# visible fan: rotating blades + spinner inside pod intake
		var rot := _new_part(ec, _comp_part(ec), fan_center, "fan_rot")
		eng["rot_part"] = rot
		var fk := _kit(rot, "metalbare")
		var nb := int(e.get("blades", 12))
		var R := float(nac["r"]) * 0.82
		for b in nb:
			var a := TAU * b / nb
			var rd := Vector3(cos(a), sin(a), 0)
			var td := Vector3(-sin(a), cos(a), 0)
			var p0 := fan_center + rd * R * 0.3
			var p1 := fan_center + rd * R
			fk.add_quad(p0 - td * R * 0.1, p1 - td * R * 0.12 + Vector3(0, 0, 0.004), p1 + td * R * 0.12 - Vector3(0, 0, 0.004), p0 + td * R * 0.1, _lin(Color(0.45, 0.46, 0.48), 0.0), true, Vector3(0, 0, -1))
			fk.add_quad(p0 + td * R * 0.1, p1 + td * R * 0.12 - Vector3(0, 0, 0.004), p1 - td * R * 0.12 + Vector3(0, 0, 0.004), p0 - td * R * 0.1, _lin(Color(0.3, 0.3, 0.32), 0.0), true, Vector3(0, 0, 1))
		var sk := _kit(rot, "plastic")
		sk.add_lathe([Vector2(0, 0.0005), Vector2(R * 0.2, R * 0.25), Vector2(R * 0.45, R * 0.3)], fan_center + Vector3(0, 0, -R * 0.35), Basis(), 12, MeshKit.const_color(_lin(Color(0.1, 0.1, 0.1))))
		var dp := _new_part(ec, _comp_part(ec), fan_center, "fan_disc")
		eng["disc_part"] = dp
		_disc_mesh(_kit(dp, "disc"), fan_center + Vector3(0, 0, 0.001), R * 0.28, R)
		eng["disc_color"] = Color(0.4, 0.4, 0.42)
		return
	# internal fan / turbine: intakes on the airframe + nozzle at the tail
	var dark := MeshKit.const_color(Color(0.02, 0.02, 0.025))
	var iz := float(e.get("intake_z", length * 0.4))
	if ei == 0 or intake == "sides_single":
		var kit := _kit(_comp_part(core), "body")
		var dk := _kit(_comp_part(core), "cockpit")
		var fp := _fus_param(iz + 0.1)
		if intake == "sides" or intake == "sides_single":
			var sides := [-1, 1] if intake == "sides" else [signf(pos.x) if pos.x != 0.0 else 1.0]
			for side in sides:
				var c := Vector3(side * fp[0] * 0.92, fp[2] - fp[1] * 0.05, iz + 0.14)
				var rr := Vector3(fp[0] * 0.42, fp[1] * 0.62, 0.16)
				if intake == "sides_single":
					rr = Vector3(fp[0] * 0.3, fp[1] * 0.9, 0.2)
				# half-bulge duct (only outer half visible, rest inside fuselage)
				kit.add_ellipsoid(c, rr, 14, 8, _pfn("fus"))
				var ring := PackedVector3Array()
				for i in 14:
					var a := TAU * i / 14.0
					ring.append(c + Vector3(cos(a) * rr.x * 0.82, sin(a) * rr.y * 0.82, -rr.z * 0.6))
				dk.add_cap(c + Vector3(0, 0, -rr.z * 0.6), ring, Vector3(0, 0, -1), dark)
		elif intake == "belly":
			var c2 := Vector3(0, fp[2] - fp[1] * 0.95, iz + 0.25)
			var rr2 := Vector3(fp[0] * 0.55, fp[1] * 0.45, 0.35)
			kit.add_ellipsoid(c2, rr2, 16, 8, _pfn("fus"))
			var ring2 := PackedVector3Array()
			for i in 16:
				var a := TAU * i / 16.0
				ring2.append(c2 + Vector3(cos(a) * rr2.x * 0.85, sin(a) * rr2.y * 0.8, -rr2.z * 0.72))
			dk.add_cap(c2 + Vector3(0, 0, -rr2.z * 0.72), ring2, Vector3(0, 0, -1), dark)
	# nozzle
	var tz := float(d["fuselage"][d["fuselage"].size() - 1][0])
	var tfp := _fus_param(tz)
	var nk := _kit(_comp_part(int(cidx["tail_boom"])), "metalbare" if t == "turbine" else "cockpit")
	var noz_r: float = minf(tfp[0], tfp[1]) * 0.95
	var nc := Vector3(pos.x if intake == "sides_single" else 0.0, tfp[2], tz)
	if intake == "sides_single":
		noz_r *= 0.5
	var ncol := MeshKit.const_color(_lin(Color(0.35, 0.33, 0.3), 0.0)) if t == "turbine" else dark
	nk.add_lathe([Vector2(-0.01, noz_r * 1.0), Vector2(0.02, noz_r * 0.92), Vector2(0.04 if t == "turbine" else 0.005, noz_r * 0.86)], nc + Vector3(0, 0, 0.0), Basis(), 16, ncol)
	var inner := PackedVector3Array()
	for i in 16:
		var a := TAU * i / 16.0
		inner.append(nc + Vector3(cos(a), sin(a), 0) * noz_r * 0.9 + Vector3(0, 0, -0.012))
	_kit(_comp_part(int(cidx["tail_boom"])), "cockpit").add_cap(nc + Vector3(0, 0, -0.012), inner, Vector3(0, 0, 1), MeshKit.const_color(Color(0.01, 0.01, 0.01)))
	eng["nozzle"] = nc

func _disc_mesh(dk: MeshKit, c: Vector3, rin: float, R: float) -> void:
	var segs := 24
	for k in segs:
		var a0 := TAU * float(k) / segs
		var a1 := TAU * float(k + 1) / segs
		var i0 := dk.verts.size()
		for q in [[c + Vector3(cos(a0), sin(a0), 0) * rin, Vector2(0, float(k) / segs)], [c + Vector3(cos(a1), sin(a1), 0) * rin, Vector2(0, float(k + 1) / segs)],
				[c + Vector3(cos(a1), sin(a1), 0) * R, Vector2(1, float(k + 1) / segs)], [c + Vector3(cos(a0), sin(a0), 0) * R, Vector2(1, float(k) / segs)]]:
			dk.verts.append(q[0]); dk.norms.append(Vector3(0, 0, -1)); dk.cols.append(Color.WHITE); dk.uvs.append(q[1])
		for l in [dk.idx, dk.lod1, dk.lod2]:
			l.append_array(PackedInt32Array([i0, i0 + 2, i0 + 1, i0, i0 + 3, i0 + 2]))

# ---------------------------------------------------------------- landing gear
func _tire(kit: MeshKit, c: Vector3, r: float, w: float, col: Callable, bush := false) -> void:
	var rt := w * 0.5
	var R := r - rt
	var prof := []
	var n := 10 if lod_detail >= 1 else 6
	for i in n + 1:
		# clockwise in (axial, radius) plane: start inner-left, over the top, to inner-right
		var a := PI - PI * float(i) / n   # PI -> 0
		var ax := cos(a) * rt * (0.9 if not bush else 1.0)
		var rr := R + sin(a) * rt * (1.0 if not bush else 1.15)
		prof.append(Vector2(-ax, rr))
	# lathe about the x axis
	var bas := Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0))
	kit.add_lathe(prof, c, bas, 20 if lod_detail >= 1 else 10, col)

var _cg_target_z := 0.0

func _estimate_cg_target() -> float:
	var area_sum := 0.0
	var c_mac := 0.0
	var zle := 0.0
	for w in d["wings"]:
		var m := _mac_of(w)
		area_sum += float(m["area"])
	for w in d["wings"]:
		var m := _mac_of(w)
		c_mac += float(m["c"]) * float(m["area"]) / area_sum
		zle += float(m["zle"]) * float(m["area"]) / area_sum
	return zle + (float(d["cg"]) + float(cfg.get("cg", 0.0))) * c_mac

func _build_wheel(wd: Dictionary, gi: int) -> void:
	var core := int(cidx["fuselage"])
	var c := Vector3(float(wd["x"]), float(wd["y"]), float(wd["z"]))
	# keep the gear geometry physically sensible around the CG
	var tricycle := String(d["gear"]["type"]) == "tricycle"
	if tricycle and not bool(wd["steer"]):
		c.z = maxf(c.z, _cg_target_z + length * 0.055)
	elif not tricycle and not bool(wd["tail"]):
		c.z = minf(c.z, _cg_target_z - length * 0.06)
	var L := float(wd["len"])
	var r := float(wd["r"])
	var w := float(wd["w"])
	var style := String(wd["style"])
	var tail := bool(wd["tail"])
	# ground clearance: the hull must stay clear even at full suspension travel
	if not tail:
		var fpg := _fus_param(c.z)
		var hull_bottom: float = float(fpg[2]) - float(fpg[1]) * 0.86
		if absf(c.x) > float(fpg[0]) * 1.6:
			hull_bottom = 99.0
		var travel0 := clampf(L * (0.45 if style in ["oleo", "bogie"] else 0.3), 0.012, r * 1.3)
		var need := hull_bottom - (travel0 * 1.2 + 0.015)
		# propeller ground clearance in a level stance (tricycle at rest, taildragger with the tail up)
		if true:
			for e in d["engines"]:
				if String(e["type"]) in ["electric", "glow2", "glow4", "gas2"]:
					var pr := _prop_choice(e)
					var tip_y: float = float((e["pos"] as Vector3).y) - float(pr["d"]) * 0.5
					# taildraggers flare and touch down on the mains in a shallow attitude, so give them more prop margin
					need = minf(need, tip_y - travel0 * 1.2 - (0.05 if not tricycle else 0.03))
		if c.y - r > need:
			var dy := (c.y - r) - need
			c.y -= dy
			L += dy
	var host := core
	if tail:
		host = int(cidx["tail_boom"])
	elif absf(c.x) > 0.13 and not d["wings"].is_empty() and float(d["wings"][0]["y"]) < 0.0:
		host = _find_wing_comp(c.x)
	var gc := _add_comp("gear%d" % gi, host, "gear", 1.0)
	comps[gc]["center"] = c + Vector3(0, L * 0.5, 0)
	var top := c + Vector3(0, L, 0)
	if style in ["spring", "wire", "bush"]:
		top = Vector3(signf(c.x) * 0.01, c.y + L, c.z)
	var gpart := _comp_part(gc)
	var retract := _new_part(gc, gpart, top, "retract")
	var slider := _new_part(gc, retract, top, "slider")
	var steer := _new_part(gc, slider, c, "steer")
	var spin := _new_part(gc, steer, c, "spin")
	var strut := _kit(retract, "metalbare" if style == "oleo" else "body")
	var chrome := _kit(slider, "metalbare")
	var metal := MeshKit.const_color(_lin(Color(0.72, 0.73, 0.75), 0.0))
	var dark := MeshKit.const_color(_lin(Color(0.15, 0.15, 0.16)))
	var sc := _pfn("strut")
	match style:
		"oleo":
			strut.add_cylinder(top, top + Vector3(0, -L * 0.55, 0), r * 0.22, r * 0.2, 8, MeshKit.const_color(_lin(Color(0.25, 0.26, 0.27), 0.0)))
			chrome.add_cylinder(top + Vector3(0, -L * 0.5, 0), c + Vector3(0, r * 0.2, 0), r * 0.13, r * 0.13, 8, metal)
			# fork / axle
			var side := signf(c.x) if absf(c.x) > 0.001 else 1.0
			chrome.add_cylinder(c + Vector3(0, r * 0.2, 0), c + Vector3(-side * w * 0.7, 0, 0), r * 0.08, r * 0.08, 6, metal, true, true)
		"spring", "wire":
			var thick := 0.003 if style == "wire" else 0.006
			var knee := Vector3(c.x * 0.85, c.y + L * 0.25, c.z)
			var k2 := _kit(retract, "body" if style == "spring" else "metalbare")
			k2.add_cylinder(top, knee, thick, thick, 6, sc if style == "spring" else metal)
			k2.add_cylinder(knee, c + Vector3(-signf(c.x) * w * 0.6, 0, 0), thick, thick, 6, sc if style == "spring" else metal)
			if absf(c.x) < 0.001:
				k2.add_cylinder(top, c + Vector3(0, r * 0.3, 0), thick, thick, 6, metal)
		"bush":
			var fus_b := Vector3(signf(c.x) * 0.03, c.y + L, c.z - 0.05)
			var fus_b2 := Vector3(signf(c.x) * 0.03, c.y + L, c.z + 0.06)
			var k3 := _kit(retract, "body")
			k3.add_cylinder(fus_b, c + Vector3(-signf(c.x) * w * 0.55, 0, 0), 0.005, 0.005, 6, sc)
			k3.add_cylinder(fus_b2, c + Vector3(-signf(c.x) * w * 0.55, 0, 0), 0.005, 0.005, 6, sc)
			k3.add_cylinder(Vector3(0, c.y + L, c.z), c + Vector3(-signf(c.x) * w * 0.55, r * 0.2, 0), 0.004, 0.004, 6, dark)
		"strut":
			var k4 := _kit(retract, "body")
			k4.add_cylinder(top + Vector3(0, 0, -0.03), c, 0.006, 0.005, 6, sc)
			k4.add_cylinder(top + Vector3(0, 0, 0.03), c, 0.006, 0.005, 6, sc)
		"tail":
			var k5 := _kit(retract, "metalbare")
			k5.add_cylinder(top + Vector3(0, 0, -0.04), c + Vector3(0, r * 0.5, 0), 0.0022, 0.0022, 5, metal)
		"pod":
			var k6 := _kit(_comp_part(core), "body")
			var fp := _fus_param(c.z)
			k6.add_ellipsoid(Vector3(signf(c.x) * fp[0] * 0.95, c.y + r * 1.4, c.z), Vector3(0.05, r * 1.6, r * 3.2), 12, 6, _pfn("fus"))
			strut.add_cylinder(top, c, r * 0.15, r * 0.15, 6, metal)
		"bogie":
			strut.add_cylinder(top, top + Vector3(0, -L * 0.55, 0), r * 0.25, r * 0.22, 8, MeshKit.const_color(_lin(Color(0.3, 0.3, 0.32), 0.0)))
			chrome.add_cylinder(top + Vector3(0, -L * 0.5, 0), c + Vector3(0, r * 0.3, 0), r * 0.15, r * 0.15, 8, metal)
			chrome.add_cylinder(c + Vector3(0, 0, -r * 1.3), c + Vector3(0, 0, r * 1.3), r * 0.1, r * 0.1, 6, metal, true, true)
	# tires + hubs
	var tk := _kit(spin, "rubber")
	var hk := _kit(spin, "metalbare" if style in ["oleo", "bogie", "pod"] else "plastic")
	var hcol := metal if style in ["oleo", "bogie", "pod"] else MeshKit.const_color(_lin(Color(0.85, 0.85, 0.85)))
	var tcol := MeshKit.const_color(_lin(Color(0.045, 0.045, 0.05)))
	var centers := [c]
	if style == "bogie":
		centers = [c + Vector3(-w * 0.62, 0, -r * 1.15), c + Vector3(w * 0.62, 0, -r * 1.15), c + Vector3(-w * 0.62, 0, r * 1.15), c + Vector3(w * 0.62, 0, r * 1.15)]
	elif bool(wd.get("twin", false)):
		centers = [c + Vector3(-w * 0.62, 0, 0), c + Vector3(w * 0.62, 0, 0)]
	for cc in centers:
		_tire(tk, cc, r, w, tcol, style == "bush")
		hk.add_cylinder(cc + Vector3(-w * 0.36, 0, 0), cc + Vector3(w * 0.36, 0, 0), (r - w * 0.5) * 0.95, (r - w * 0.5) * 0.95, 12 if lod_detail >= 1 else 6, hcol)
		if lod_detail >= 2:
			hk.add_cylinder(cc + Vector3(-w * 0.45, 0, 0), cc + Vector3(w * 0.45, 0, 0), r * 0.12, r * 0.12, 6, MeshKit.const_color(_lin(Color(0.3, 0.3, 0.3))), true, true)
	if bool(wd["pants"]):
		var pk := _kit(slider, "body")
		pk.add_ellipsoid(c + Vector3(0, r * 0.2, r * 0.3), Vector3(w * 0.78, r * 0.84, r * 1.75), 18, 10, _pfn("pant"))
	var retract_axis := Vector3(0, 0, 1) * (-signf(c.x) if absf(c.x) > 0.001 else 1.0)
	var retract_angle := deg_to_rad(88.0)
	if absf(c.x) < 0.001:
		retract_axis = Vector3(1, 0, 0)
		retract_angle = deg_to_rad(95.0) if c.z < length * 0.5 else deg_to_rad(-80.0)
	# suspension travel is much shorter than the visual leg (spring legs flex a few cm)
	var travel := clampf(L * (0.45 if style in ["oleo", "bogie"] else 0.3), 0.012, r * 1.3)
	wheels.append({"top": top, "center": c, "len": L, "travel": travel, "r": r, "w": w, "steer": bool(wd["steer"]), "brake": bool(wd["brake"]),
		"tail": tail, "comp": gc, "retract_part": retract, "slider_part": slider, "steer_part": steer, "spin_part": spin,
		"retract_axis": retract_axis, "retract_angle": retract_angle, "k_scale": float(wd["k_scale"]), "style": style,
		"retractable": bool(d["gear"]["retract"])})

# ---------------------------------------------------------------- details
func _build_details() -> void:
	var core := int(cidx["fuselage"])
	var det: Dictionary = d["details"]
	var ck := _kit(_comp_part(core), "body")
	if lod_detail >= 2:
		# antenna behind the canopy
		var az := float(d["canopy"].get("z1", length * 0.5)) + length * 0.06
		if az < z_split:
			var fp := _fus_param(az)
			var ak := _kit(_comp_part(core), "cockpit")
			ak.add_cylinder(Vector3(0, fp[2] + fp[1] * 0.95, az), Vector3(0, fp[2] + fp[1] * 0.95 + length * 0.05, az + length * 0.02), 0.0015, 0.0008, 4, MeshKit.const_color(Color(0.05, 0.05, 0.05)), false, true)
	if bool(det.get("scoop", false)):
		var sz := length * 0.55
		var fp2 := _fus_param(sz)
		ck.add_ellipsoid(Vector3(0, fp2[2] - fp2[1] * 0.95, sz), Vector3(fp2[0] * 0.6, fp2[1] * 0.35, length * 0.13), 14, 8, _pfn("fus"))
		var dk := _kit(_comp_part(core), "cockpit")
		var ring := PackedVector3Array()
		for i in 12:
			var a := TAU * i / 12.0
			ring.append(Vector3(cos(a) * fp2[0] * 0.45, fp2[2] - fp2[1] * 1.05 + sin(a) * fp2[1] * 0.18, sz - length * 0.1))
		dk.add_cap(Vector3(0, fp2[2] - fp2[1] * 1.05, sz - length * 0.1), ring, Vector3(0, 0, -1), MeshKit.const_color(Color(0.02, 0.02, 0.02)))
	if bool(det.get("gun", false)):
		var mk2 := _kit(_comp_part(core), "metalbare")
		mk2.add_cylinder(Vector3(0, -0.02, -0.03), Vector3(0, -0.02, 0.02), 0.006, 0.006, 8, MeshKit.const_color(_lin(Color(0.2, 0.2, 0.2), 0.0)), true, true)
	if bool(det.get("belly_fairing", false)):
		# wing-to-body fairing (airliners): a smooth lofted blister under the wing root
		var w0: Dictionary = d["wings"][0]
		var wzc := float(w0["z"]) + float(w0["root"]) * 0.42
		var fpb := _fus_param(wzc)
		ck.add_ellipsoid(Vector3(0, float(fpb[2]) - float(fpb[1]) * 0.80, wzc), Vector3(float(fpb[0]) * 1.02, float(fpb[1]) * 0.30, float(w0["root"]) * 0.62), 16, 8, _pfn("fus"))
	if det.has("ramp") and lod_detail >= 1:
		# rear cargo ramp / door outline and paratroop doors, as dark panel seams on the skin
		var rz: Array = det["ramp"]
		var sk := _kit(_comp_part(core), "cockpit")
		var seam := MeshKit.const_color(Color(0.05, 0.05, 0.06))
		var th2 := 0.0011
		var steps := 8
		for side in [-1.0, 1.0]:
			var prev := Vector3.ZERO
			for i in steps + 1:
				var zz := lerpf(float(rz[0]), float(rz[1]), float(i) / steps)
				var fpr := _fus_param(zz)
				var ang := deg_to_rad(-90.0 + side * 38.0)
				var e := 2.0 / maxf(float(fpr[3]), 1.0)
				var pr := Vector3(signf(cos(ang)) * pow(absf(cos(ang)), e) * float(fpr[0]) * 1.002, signf(sin(ang)) * pow(absf(sin(ang)), e) * float(fpr[1]) + float(fpr[2]), zz)
				if i > 0:
					sk.add_cylinder(prev, pr, th2, th2, 4, seam, false, true)
				prev = pr
		for zz in [float(rz[0]), float(rz[1])]:
			var fpr2 := _fus_param(zz)
			var e2 := 2.0 / maxf(float(fpr2[3]), 1.0)
			var prev2 := Vector3.ZERO
			for i in 7:
				var ang2 := deg_to_rad(-90.0 - 38.0 + 76.0 * float(i) / 6.0)
				var pr2 := Vector3(signf(cos(ang2)) * pow(absf(cos(ang2)), e2) * float(fpr2[0]) * 1.002, signf(sin(ang2)) * pow(absf(sin(ang2)), e2) * float(fpr2[1]) + float(fpr2[2]), zz)
				if i > 0:
					sk.add_cylinder(prev2, pr2, th2, th2, 4, seam, false, true)
				prev2 = pr2
		# paratroop doors
		var pz0 := float(rz[0]) - 0.16
		var fpd := _fus_param(pz0 + 0.05)
		for side in [-1.0, 1.0]:
			var x: float = side * (float(fpd[0]) * 1.002)
			var yc: float = float(fpd[2]) + float(fpd[1]) * 0.1
			var c1 := Vector3(x, yc - 0.035, pz0)
			var c2 := Vector3(x, yc - 0.035, pz0 + 0.1)
			var c3 := Vector3(x, yc + 0.04, pz0 + 0.1)
			var c4 := Vector3(x, yc + 0.04, pz0)
			sk.add_cylinder(c1, c2, th2, th2, 4, seam, false, true)
			sk.add_cylinder(c2, c3, th2, th2, 4, seam, false, true)
			sk.add_cylinder(c3, c4, th2, th2, 4, seam, false, true)
			sk.add_cylinder(c4, c1, th2, th2, 4, seam, false, true)
	if bool(det.get("windows", false)) and lod_detail >= 1:
		var tb := int(cidx["tail_boom"])
		var z := length * 0.12
		while z < length * 0.84:
			var fp3 := _fus_param(z)
			for side in [-1, 1]:
				var pz := Vector3(side * (fp3[0] + 0.0006), fp3[2] + fp3[1] * 0.28, z)
				var host := core if z < z_split else tb
				var wk := _kit(_comp_part(host), "cockpit")
				var n := Vector3(side, 0, 0)
				wk.add_quad(pz + Vector3(0, -0.005, -0.004), pz + Vector3(0, -0.005, 0.004), pz + Vector3(0, 0.005, 0.004), pz + Vector3(0, 0.005, -0.004), Color(0.03, 0.04, 0.06), true, n)
			z += 0.019

# ---------------------------------------------------------------- fuselage aero / drag
var body_drag: Dictionary = {}

func _build_body_panels() -> void:
	var st: Array = d["fuselage"]
	var z0 := float(st[0][0])
	var z1 := float(st[st.size() - 1][0])
	var n := 40
	var side_a := 0.0
	var top_a := 0.0
	var mz_s := 0.0
	var mz_t := 0.0
	var ymean := 0.0
	var front := 0.0
	var dz := (z1 - z0) / n
	for i in n:
		var z := z0 + (i + 0.5) * dz
		var fp := _fus_param(z)
		side_a += 2.0 * fp[1] * dz
		top_a += 2.0 * fp[0] * dz
		mz_s += 2.0 * fp[1] * dz * z
		mz_t += 2.0 * fp[0] * dz * z
		ymean += fp[2] * dz
		front = maxf(front, PI * fp[0] * fp[1])
	ymean /= (z1 - z0)
	var zs := mz_s / maxf(side_a, 1e-5)
	var zt := mz_t / maxf(top_a, 1e-5)
	var core := int(cidx["fuselage"])
	var cla_s := _helmbold(0.35)
	panels.append(_panel(Vector3(0, ymean, zs), Vector3(0, 0, -1), Vector3(1, 0, 0), side_a, 0.35, (z1 - z0) * 0.5, cla_s, 0.0, 35.0, 0.0, core, [], "body"))
	panels.append(_panel(Vector3(0, ymean, zt), Vector3(0, 0, -1), Vector3(0, 1, 0), top_a, 0.35, (z1 - z0) * 0.5, cla_s, 0.0, 35.0, 0.0, core, [], "body"))
	var gear_cda := 0.0
	for wd in d["gear"]["wheels"]:
		gear_cda += float(wd["r"]) * float(wd["w"]) * 2.0 * (0.6 if bool(wd["pants"]) else 1.1) + float(wd["len"]) * 0.006
	body_drag = {"front_cda": front * float(d["body_cd"]), "side_cda": side_a * 0.9, "top_cda": top_a * 1.0,
		"pos": Vector3(0, ymean, (zs + zt) * 0.5), "gear_cda": gear_cda + float(d["gear_drag"]) * 0.01}

# ---------------------------------------------------------------- masses & CG
var _cg := Vector3.ZERO
var _total_mass := 1.0
var _mac := {}
var ballast := 0.0
var payload_mass := 0.0
var payload_kind := ""
var radio_mass := 0.0
var radio_z := 0.0
var cg_free := Vector2.ZERO   # CG range (fraction of MAC) reachable by sliding the battery, before any ballast

func _mac_of(w: Dictionary) -> Dictionary:
	var rc := float(w["root"])
	var tc := float(w["tip"])
	var lam := tc / rc
	var c := 2.0 / 3.0 * rc * (1.0 + lam + lam * lam) / (1.0 + lam)
	var ymac := float(w["span"]) / 6.0 * (1.0 + 2.0 * lam) / (1.0 + lam)
	var zle := float(w["z"]) + ymac * tan(deg_to_rad(float(w["sweep"])))
	return {"c": c, "zle": zle, "area": float(w["span"]) * 0.5 * (rc + tc)}

func _assign_masses() -> void:
	# weights per component
	var W := {}
	for i in comps.size():
		var c: Dictionary = comps[i]
		var k := String(c["kind"])
		var wv := 0.0
		match k:
			"fuselage":
				wv = 0.30 if c["id"] == "fuselage" else 0.055
			"engine": wv = 0.04
			"canopy": wv = 0.02
			"wing", "wingtip":
				var sr: Array = c.get("span_range", [0.0, 1.0])
				var sf: Dictionary = c["sf"]
				var a := (float(sr[1]) - float(sr[0])) * (lerpf(float(sf["rc"]), float(sf["tc"]), (float(sr[0]) + float(sr[1])) * 0.5))
				wv = a
			"control": wv = 0.0
			"stab": wv = 0.016
			"fin": wv = 0.010
			"gear": wv = 0.02
			"nacelle": wv = 0.03
			"prop": wv = 0.008
		W[i] = wv
	# normalise wing weights to 34% total
	var wing_sum := 0.0
	for i in comps.size():
		if String(comps[i]["kind"]) in ["wing", "wingtip"]:
			wing_sum += float(W[i])
	for i in comps.size():
		if String(comps[i]["kind"]) in ["wing", "wingtip"]:
			W[i] = float(W[i]) / maxf(wing_sum, 1e-5) * 0.34
		if String(comps[i]["kind"]) == "control":
			var par := int(comps[i]["parent"])
			W[i] = 0.008
			W[par] = maxf(float(W[par]) - 0.004, 0.0)
	var tot := 0.0
	for v in W.values():
		tot += float(v)
	var eng_mass := 0.0
	for e in d["engines"]:
		eng_mass += float(e["mass"])
	# Glow / gas / turbine models carry a receiver pack + servo block that the pilot positions to
	# set the CG (like a battery in an electric model). It is part of the listed mass, not extra.
	var etype0 := String(d["engines"][0]["type"])
	radio_mass = 0.0 if etype0 in ["electric", "edf"] else float(d["mass"]) * 0.09
	var structure := maxf(float(d["mass"]) - eng_mass - radio_mass, float(d["mass"]) * 0.3)
	for i in comps.size():
		var c: Dictionary = comps[i]
		c["mass"] = structure * float(W[i]) / tot
		var mn: Vector3 = c["aabb_min"]
		var mx: Vector3 = c["aabb_max"]
		if mn.x == INF:
			mn = (c["center"] as Vector3) - Vector3(0.02, 0.02, 0.02)
			mx = (c["center"] as Vector3) + Vector3(0.02, 0.02, 0.02)
		c["size"] = (mx - mn).max(Vector3(0.01, 0.01, 0.01))
		if c["center"] == Vector3.ZERO or String(c["kind"]) in ["gear", "canopy", "stab", "fin"]:
			c["center"] = (mn + mx) * 0.5
		c["point_masses"] = [{"pos": c["center"], "m": c["mass"], "size": c["size"]}]
	# engines
	for e in engines:
		var ec: Dictionary = comps[int(e["comp"])]
		(ec["point_masses"] as Array).append({"pos": e["pos"] + Vector3(0, 0, 0.03), "m": float(e["def"]["mass"]), "size": Vector3(0.05, 0.05, 0.06)})
		ec["mass"] = float(ec["mass"]) + float(e["def"]["mass"])
	# CG target
	var macs := []
	var area_sum := 0.0
	for w in d["wings"]:
		var m := _mac_of(w)
		macs.append(m)
		area_sum += float(m["area"])
	var c_mac := 0.0
	var zle := 0.0
	for m in macs:
		c_mac += float(m["c"]) * float(m["area"]) / area_sum
		zle += float(m["zle"]) * float(m["area"]) / area_sum
	_mac = {"c": c_mac, "zle": zle, "area": area_sum}
	var cg_frac := float(d["cg"]) + float(cfg.get("cg", 0.0))
	var z_target := zle + cg_frac * c_mac
	# payload: battery (electric) or fuel tank
	var etype := String(d["engines"][0]["type"])
	var core: Dictionary = comps[int(cidx["fuselage"])]
	var m0 := 0.0
	var mz := 0.0
	for c in comps:
		for pm in c["point_masses"]:
			m0 += float(pm["m"])
			mz += float(pm["m"]) * (pm["pos"] as Vector3).z
	var pay := 0.0
	var pay_z := z_target
	if etype in ["electric", "edf"]:
		var bats: Array = d["batteries"]
		if bats.size() > 0:
			pay = float(bats[clampi(int(cfg.get("battery", 0)), 0, bats.size() - 1)]["mass"])
		payload_kind = "battery"
		# battery slides in its tray to hit the CG
		pay_z = (z_target * (m0 + pay) - mz) / maxf(pay, 1e-4)
	else:
		var tank := float(d["tank"])
		var dens := 0.8 if etype != "gas2" else 0.74
		pay = tank * dens * clampf(float(cfg.get("fuel", 1.0)), 0.05, 1.0)
		payload_kind = "fuel"
		pay_z = z_target - c_mac * 0.05
	var zmin := maxf(z_nose - length * 0.03, float(d["fuselage"][0][0]) + length * 0.04)
	var zmax := z_split - 0.02
	if radio_mass > 0.0:
		# fuel tank sits at its fixed station; the radio block slides to trim the CG
		pay_z = clampf(z_target - c_mac * 0.05, zmin, zmax)
		var m_tank := m0 + pay
		var mz_tank := mz + pay * pay_z
		var rz := (z_target * (m_tank + radio_mass) - mz_tank) / radio_mass
		rz = clampf(rz, zmin, zmax)
		(core["point_masses"] as Array).append({"pos": Vector3(0, float(_fus_param(rz)[2]) - float(_fus_param(rz)[1]) * 0.35, rz), "m": radio_mass, "size": Vector3(0.05, 0.05, 0.12), "radio": true})
		core["mass"] = float(core["mass"]) + radio_mass
		m0 += radio_mass
		mz += radio_mass * rz
		radio_z = rz
	var free_lo := 0.0
	var free_hi := 0.0
	if payload_kind == "battery" and pay > 0.0:
		free_lo = (mz + pay * zmin) / (m0 + pay)
		free_hi = (mz + pay * zmax) / (m0 + pay)
	cg_free = Vector2((free_lo - float(_mac["zle"])) / maxf(c_mac, 1e-4), (free_hi - float(_mac["zle"])) / maxf(c_mac, 1e-4))
	pay_z = clampf(pay_z, zmin, zmax)
	payload_mass = pay
	(core["point_masses"] as Array).append({"pos": Vector3(0, float(_fus_param(pay_z)[2]) - float(_fus_param(pay_z)[1]) * 0.3, pay_z), "m": pay, "size": Vector3(0.05, 0.04, 0.12), "payload": true})
	core["mass"] = float(core["mass"]) + pay
	m0 += pay
	mz += pay * pay_z
	# ballast to trim the remainder (hidden lead in nose or tail)
	var cgz := mz / m0
	ballast = 0.0
	if absf(cgz - z_target) > 0.002:
		var bz := zmin if cgz > z_target else z_split - 0.05
		var need := m0 * (cgz - z_target) / (cgz - bz) if absf(cgz - bz) > 1e-4 else 0.0
		need = clampf(need, 0.0, float(d["mass"]) * 0.18)
		if need > 0.0:
			ballast = need
			(core["point_masses"] as Array).append({"pos": Vector3(0, float(_fus_param(bz)[2]), bz), "m": need, "size": Vector3(0.02, 0.02, 0.02)})
			core["mass"] = float(core["mass"]) + need
			m0 += need
			mz += need * bz
	var my := 0.0
	for c in comps:
		for pm in c["point_masses"]:
			my += float(pm["m"]) * (pm["pos"] as Vector3).y
	_total_mass = m0
	_cg = Vector3(0, my / m0, mz / m0)
	# springs: static load share per wheel
	_gear_springs()

func _gear_springs() -> void:
	if wheels.is_empty():
		return
	var g := 9.81
	# two-group support: wheels ahead of CG vs behind CG
	var ahead := []
	var behind := []
	for w in wheels:
		if (w["center"] as Vector3).z < _cg.z:
			ahead.append(w)
		else:
			behind.append(w)
	var za := 0.0
	var zb := 0.0
	for w in ahead: za += (w["center"] as Vector3).z / ahead.size()
	for w in behind: zb += (w["center"] as Vector3).z / behind.size()
	var share_a := 0.5
	if not ahead.is_empty() and not behind.is_empty():
		share_a = clampf((zb - _cg.z) / maxf(zb - za, 1e-3), 0.05, 0.95)
	elif ahead.is_empty():
		share_a = 0.0
	else:
		share_a = 1.0
	for w in wheels:
		var grp := ahead if (w["center"] as Vector3).z < _cg.z else behind
		var share := (share_a if grp == ahead else 1.0 - share_a) / maxf(grp.size(), 1)
		var load := maxf(_total_mass * g * share, _total_mass * g * 0.04)
		var static_defl := float(w["travel"]) * 0.35
		var k := load / static_defl * float(w["k_scale"])
		w["k"] = k
		w["c"] = 2.0 * 0.55 * sqrt(k * load / g)
		w["load"] = load

# ---------------------------------------------------------------- colliders
func _build_shapes() -> void:
	for i in comps.size():
		var c: Dictionary = comps[i]
		var k := String(c["kind"])
		var shapes: Array = c["shapes"]
		var mn: Vector3 = c["aabb_min"]
		var mx: Vector3 = c["aabb_max"]
		if mn.x == INF and not k in ["prop", "gear"]:
			continue
		match k:
			"fuselage", "engine":
				var za := mn.z
				var zb := mx.z
				var nseg := maxi(1, int(ceil((zb - za) / (length * 0.22))))
				for sgi in nseg:
					var z0 := lerpf(za, zb, float(sgi) / nseg)
					var z1 := lerpf(za, zb, float(sgi + 1) / nseg)
					# tapered hull following the real outline at both ends of the segment
					var pts := PackedVector3Array()
					for zz in [z0, z1]:
						var fp := _fus_param(zz)
						var hw := maxf(float(fp[0]) * 0.92, 0.01)
						var hh := maxf(float(fp[1]) * 0.9, 0.01)
						var yc := float(fp[2])
						for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
							pts.append(Vector3(corner.x * hw, yc + corner.y * hh, zz))
					shapes.append({"type": "convex", "xf": Transform3D(), "points": pts})
			"wing", "wingtip", "stab", "fin":
				if c.has("sf"):
					var sf: Dictionary = c["sf"]
					var sr: Array = c.get("span_range", [0.0, 1.0])
					var nsub := 2 if float(sf["tan_sw"]) < 0.6 else 3
					for q in nsub:
						var s0 := lerpf(float(sr[0]), float(sr[1]), float(q) / nsub)
						var s1 := lerpf(float(sr[0]), float(sr[1]), float(q + 1) / nsub)
						var le0 := _sp(sf, s0, 0.0, 0.0)
						var le1 := _sp(sf, s1, 0.0, 0.0)
						var te0 := _sp(sf, s0, 1.0, 0.0)
						var te1 := _sp(sf, s1, 1.0, 0.0)
						var sd: Vector3 = sf["span"]
						var th: Vector3 = sf["thick"]
						var ch := sd.cross(th).normalized()
						if ch.z < 0.0:
							ch = -ch
						var center := (le0 + le1 + te0 + te1) * 0.25
						var span_len := (le1 - le0).dot(sd)
						var zmin := minf((le0 - center).dot(ch), (le1 - center).dot(ch))
						var zmax := maxf((te0 - center).dot(ch), (te1 - center).dot(ch))
						var cavg := lerpf(float(sf["rc"]), float(sf["tc"]), (s0 + s1) * 0.5)
						var thk := maxf(float(sf["t"]) * cavg * 1.1, 0.014)
						var bas := Basis(sd, th, ch).orthonormalized()
						var mid_off := ch * (zmin + zmax) * 0.5
						shapes.append({"type": "box", "xf": Transform3D(bas, center + mid_off), "size": Vector3(absf(span_len), thk, (zmax - zmin) * 0.9)})
				else:
					_box_from_aabb(shapes, mn, mx, 0.012)
			"control":
				_box_from_aabb(shapes, mn, mx, 0.01)
			"canopy", "nacelle":
				_box_from_aabb(shapes, mn, mx, 0.015)
			"gear":
				for w in wheels:
					if int(w["comp"]) == i:
						var bump := (w["center"] as Vector3) + Vector3(0, float(w["travel"]) * 1.05, 0)
						shapes.append({"type": "sphere", "xf": Transform3D(Basis(), bump), "r": float(w["r"]) * 0.92, "wheel": true})
			"prop":
				for e in engines:
					if int(e["prop_comp"]) == i:
						var bas2 := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))
						shapes.append({"type": "cyl", "xf": Transform3D(bas2, e["pos"] as Vector3 + Vector3(0, 0, -0.02)), "r": float(e["D"]) * 0.48, "h": 0.02})

func _box_from_aabb(shapes: Array, mn: Vector3, mx: Vector3, minsz: float) -> void:
	var sz := (mx - mn).max(Vector3(minsz, minsz, minsz))
	shapes.append({"type": "box", "xf": Transform3D(Basis(), (mn + mx) * 0.5), "size": sz})

# ---------------------------------------------------------------- meshes & labels
func _material_for(key: String) -> Material:
	match key:
		"body": return MatLib.aircraft(mk)
		"glass": return MatLib.glass(d["canopy"].get("tint", Color(0.1, 0.12, 0.15)))
		"plastic": return MatLib.aircraft("plastic")
		"cockpit": return MatLib.aircraft("cockpit")
		"metalbare": return MatLib.aircraft("metal")
		"rubber": return MatLib.aircraft("rubber")
		"nav_red": return MatLib.emissive(Color(1.0, 0.1, 0.05), 3.0)
		"nav_green": return MatLib.emissive(Color(0.1, 1.0, 0.2), 3.0)
		"carbon": return MatLib.aircraft("carbon")
		"disc":
			return MatLib.prop_disc(Color(0.05, 0.05, 0.06), Color(0.95, 0.9, 0.2) if scheme == "p51" else Color(0.9, 0.9, 0.9), 0.08 if scheme in ["p51", "cargo", "t28", "hog"] else 0.0, 3)
	return MatLib.aircraft("plastic")

func _finalize_meshes() -> void:
	for p in parts:
		var kits: Dictionary = p["kits"]
		if kits.is_empty():
			continue
		var mesh := ArrayMesh.new()
		var origin: Vector3 = p["origin"]
		var keys := kits.keys()
		keys.sort()
		var has_disc := false
		for key in keys:
			var kit: MeshKit = kits[key]
			if kit.is_empty():
				continue
			kit.offset(-origin)
			if key == "disc":
				has_disc = true
			kit.append_to(mesh, _material_for(key), length * 0.01, length * 0.03)
		if mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = "Mesh"
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if has_disc else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		(p["node"] as Node3D).add_child(mi)
		p["mesh"] = mi

func _place_labels() -> void:
	if lod_detail < 1:
		return
	for lab in d["labels"]:
		var text := String(lab["text"])
		var size := float(lab["size"])
		var colr: Color = lab["color"]
		var z := float(lab["z"])
		if bool(lab.get("vtail", false)):
			if d["vtails"].is_empty():
				continue
			var fin_id := "fin0" if cidx.has("fin0") else "fin0R"
			if not cidx.has(fin_id):
				continue
			var fc: Dictionary = comps[int(cidx[fin_id])]
			var sf: Dictionary = fc["sf"]
			var y := float(lab["y"])
			# find span fraction for y
			var s := clampf((y - (sf["root"] as Vector3).y) / (float(sf["half"]) * (sf["span"] as Vector3).y), 0.05, 0.95)
			var mid := _sp(sf, s, 0.45, 0.0)
			var cth := lerpf(float(sf["rc"]), float(sf["tc"]), s) * float(sf["t"]) * 0.5 + 0.0015
			for side in [-1, 1]:
				var l := _label(text, size, colr)
				l.position = mid + (sf["thick"] as Vector3) * cth * side
				l.basis = Basis(Vector3.UP, PI * 0.5 * side)
				(fc["visual"] as Node3D).add_child(l)
		else:
			var fp := _fus_param(z)
			var host := int(cidx["fuselage"]) if z < z_split else int(cidx["tail_boom"])
			var y := float(fp[2]) + float(lab.get("y", 0.0))
			# The decal is a flat card. Sample the fuselage skin over the whole text length, push the
			# card out to the widest point (so no letter is buried by a swelling fuselage) and yaw it
			# to follow the skin slope, instead of clipping the ends of the word.
			var ext := float(text.length()) * size * 0.6
			var zs0 := z - ext * 0.5
			var zs1 := z + ext * 0.5
			var xmax := 0.0
			var xa := 0.0
			var xb := 0.0
			for si in 9:
				var zz := lerpf(zs0, zs1, float(si) / 8.0)
				var fq := _fus_param(zz)
				var xq := 0.0
				# the card is also ~text-height tall: the skin falls away toward the crown, so take the widest point
				for dy in [0.0, -0.5, 0.5]:
					var relq := clampf((y + dy * size - float(fq[2])) / float(fq[1]), -0.95, 0.95)
					xq = maxf(xq, pow(absf(cos(asin(relq))), 2.0 / float(fq[3])) * float(fq[0]))
				xmax = maxf(xmax, xq)
				if si == 0: xa = xq
				if si == 8: xb = xq
			var slope := (xb - xa) / maxf(ext, 0.001)
			# keep the card outside the skin everywhere along its length (mm-scale stand-off)
			var xs := xmax + 0.0015
			for side in [-1, 1]:
				var l2 := _label(text, size, colr)
				l2.position = Vector3(side * xs, y, z)
				var nrm2 := Vector2(float(side), -slope)
				l2.basis = Basis(Vector3.UP, atan2(nrm2.x, nrm2.y))
				(comps[host]["visual"] as Node3D).add_child(l2)

func _label(text: String, size: float, colr: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 160
	l.outline_size = 0
	l.pixel_size = size / 160.0
	l.modulate = colr
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return l

# ---------------------------------------------------------------- fracture interiors
func _fracture_pair(parent: int, child: int, loop: PackedVector3Array, normal: Vector3) -> void:
	if loop.size() < 3: return
	var center := _centroid(loop)
	var nodes: Array = []
	for side: float in [1.0, -1.0]:
		var k := MeshKit.new()
		var inward := normal * (-side)
		var rim := PackedVector3Array()
		var depth := clampf(length * 0.009, 0.003, 0.018)
		for i in loop.size():
			# Fixed geometric variation, not RNG: building art must not change physics RNG.
			var offset := (sin(float(i) * 5.17) * 0.5 + 0.5) * depth * 0.22
			rim.append(loop[i] + inward * (0.001 + offset))
		if mk == "foam":
			var recess := center + inward * depth * 0.28
			for i in rim.size():
				var shade := 0.92 + 0.06 * sin(float(i) * 3.7)
				k.add_triangle(recess, rim[i], rim[(i + 1) % rim.size()], _lin(Color(0.93,0.92,0.84) * shade), false, normal * side)
		else:
			var is_wood := mk in ["film", "fabric"]
			var col := _lin(Color(0.69,0.48,0.25) if is_wood else Color(0.22,0.24,0.25))
			var factor := 0.84 if is_wood else 0.94
			for i in rim.size():
				var a := rim[i]
				var b := rim[(i + 1) % rim.size()]
				var ai := center.lerp(a, factor)
				var bi := center.lerp(b, factor)
				k.add_quad(a, b, bi, ai, col, false, normal * side)
				k.add_quad(ai, bi, bi + inward * depth * 2.0, ai + inward * depth * 2.0, col.darkened(0.2))
			# A recessed internal cross member makes a hollow frame readable.
			var a := center.lerp(rim[0], 0.85) + inward * depth
			var b := center.lerp(rim[rim.size() / 2], 0.85) + inward * depth
			k.add_cylinder(a, b, depth * 0.28, depth * 0.28, 6, MeshKit.const_color(col))
		# Shared carbon reinforcing spar is exposed at the separation, not floating outside.
		k.add_cylinder(center + inward * depth * 1.5, center - inward * depth * 0.1,
			depth * 0.4, depth * 0.38, 8, MeshKit.const_color(_lin(Color(0.09,0.1,0.11))))
		var mesh := ArrayMesh.new()
		k.append_to(mesh, MatLib.aircraft("foam" if mk == "foam" else "plastic"))
		var mi := MeshInstance3D.new()
		mi.name = "FractureInterior"
		mi.mesh = mesh
		mi.visible = false
		mi.visibility_range_end = 45.0
		mi.visibility_range_end_margin = 8.0
		(comps[parent if side > 0.0 else child]["visual"] as Node3D).add_child(mi)
		nodes.append(mi)
	fractures.append({"parent": parent, "child": child, "nodes": nodes})
