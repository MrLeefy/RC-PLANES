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
			var q := Vector2(p.x * 1.3 + p.z * 0.7, p.z * 1.1 - p.x * 0.6 + p.y * 2.0) * 7.0
			var cell := int(floor(q.x)) * 7 + int(floor(q.y)) * 13
			var t := cell % 3
			col = base if t == 0 else (a1 if t == 1 else base.lerp(a1, 0.5))
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
	return func(p: Vector3, n: Vector3) -> Color: return paint(zone, p, n)

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
	var segs := 24 if lod_detail >= 1 else 12
	var nrows := 44 if lod_detail >= 1 else 16
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
	var nsp := maxi(2, int(ceil((s1 - s0) * float(sf["half"]) / 0.05)) + 1)
	if lod_detail == 0:
		nsp = 2
	var ncs := 10 if lod_detail >= 1 else 5
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