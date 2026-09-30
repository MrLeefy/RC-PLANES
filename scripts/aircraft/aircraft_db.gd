class_name AircraftDB
extends RefCounted
## Data-driven aircraft definitions. Geometry AND physics are derived from these
## numbers (areas, arms, masses, inertia), so there is no per-aircraft physics code.
##
## Coordinates (metres): x = right, y = up, z = aft. z = 0 is the nose/spinner tip.
## Fuselage stations: [z, half_width, half_height, center_y, superellipse_exponent]
## All liveries/names are original RC Park designs (no real brands/logos).

static var _cache: Array = []

static func all() -> Array:
	if _cache.is_empty():
		_cache = _build()
	return _cache

static func by_id(id: String) -> Dictionary:
	for d in all():
		if d["id"] == id:
			return d
	return all()[0]

static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for d in all():
		out.append(d["id"])
	return out

# ---------------------------------------------------------------- helpers
static func _batt(name: String, cells: int, cap: float, mass: float) -> Dictionary:
	return {"name": name, "cells": cells, "cap": cap, "mass": mass}

static func _prop(name: String, d_in: float, p_in: float, blades := 2) -> Dictionary:
	return {"name": name, "d": d_in * 0.0254, "pitch": p_in * 0.0254, "blades": blades}

static func _wing(z: float, y: float, span: float, rc: float, tc: float, o: Dictionary = {}) -> Dictionary:
	var w := {
		"z": z, "y": y, "span": span, "root": rc, "tip": tc, "sweep": 0.0, "dihedral": 2.0,
		"incidence": 1.0, "washout": 1.0, "thick": 0.12, "camber": 0.02, "x0": 0.0,
		"ail": [0.5, 0.95, 0.25], "flap": [], "slats": false, "struts": false, "tip_style": "round",
		"stall_deg": 15.0, "elevon": false,
	}
	w.merge(o, true)
	return w

static func _htail(z: float, y: float, span: float, rc: float, tc: float, o: Dictionary = {}) -> Dictionary:
	var h := {"z": z, "y": y, "span": span, "root": rc, "tip": tc, "sweep": 8.0, "dihedral": 0.0,
		"thick": 0.08, "elev_cf": 0.4, "stabilator": false, "taileron": 0.0, "incidence": 0.0}
	h.merge(o, true)
	return h

static func _vtail(z: float, y: float, height: float, rc: float, tc: float, o: Dictionary = {}) -> Dictionary:
	var v := {"z": z, "y": y, "x": 0.0, "height": height, "root": rc, "tip": tc, "sweep": 25.0,
		"thick": 0.08, "rudder_cf": 0.4, "cant": 0.0, "mirror": false}
	v.merge(o, true)
	return v

static func _elec(pos: Vector3, kv: float, rm: float, i0: float, mass: float, o: Dictionary = {}) -> Dictionary:
	var e := {"type": "electric", "pos": pos, "dir": Vector3(0, 0, -1), "kv": kv, "rm": rm, "i0": i0,
		"mass": mass, "spin": 1, "nacelle": {}, "spinner_r": 0.03, "spinner_len": 0.06}
	e.merge(o, true)
	return e

static func _ic(kind: String, pos: Vector3, qmax: float, rpm_peak: float, rpm_max: float, mass: float, o: Dictionary = {}) -> Dictionary:
	# kind: glow2, glow4, gas2
	var e := {"type": kind, "pos": pos, "dir": Vector3(0, 0, -1), "qmax": qmax, "rpm_peak": rpm_peak,
		"rpm_max": rpm_max, "mass": mass, "spin": 1, "idle": 0.2, "nacelle": {}, "spinner_r": 0.035,
		"spinner_len": 0.07, "bsfc": 1.0}
	e.merge(o, true)
	return e

static func _edf(pos: Vector3, dia_mm: float, thrust_n: float, v_exit: float, amps: float, mass: float, o: Dictionary = {}) -> Dictionary:
	var e := {"type": "edf", "pos": pos, "dir": Vector3(0, 0, -1), "fan_d": dia_mm / 1000.0,
		"thrust": thrust_n, "v_exit": v_exit, "amps": amps, "mass": mass, "spool": 0.22,
		"rpm_max": 38000.0 * 90.0 / dia_mm, "spin": 1, "nacelle": {}, "intake": "nose", "blades": 12}
	e.merge(o, true)
	return e

static func _turbine(pos: Vector3, thrust_n: float, mass: float, o: Dictionary = {}) -> Dictionary:
	var e := {"type": "turbine", "pos": pos, "dir": Vector3(0, 0, -1), "thrust": thrust_n,
		"rpm_max": 152000.0, "idle_frac": 0.36, "mass": mass, "spool_up": 1.6, "spool_down": 1.1,
		"v_exit": 330.0, "burn": 0.0035, "spin": 1, "nacelle": {}, "fan_d": 0.1, "intake": "belly"}
	e.merge(o, true)
	return e

static func _wheel(x: float, y: float, z: float, r: float, o: Dictionary = {}) -> Dictionary:
	var w := {"x": x, "y": y, "z": z, "r": r, "w": r * 0.55, "len": 0.1, "steer": false,
		"style": "spring", "pants": false, "k_scale": 1.0, "tail": false, "brake": true}
	w.merge(o, true)
	return w

static func _base(o: Dictionary) -> Dictionary:
	var d := {
		"id": "", "name": "", "category": "", "blurb": "", "material": "foam",
		"mass": 1.0, "length": 1.0, "fuselage": [], "canopy": {}, "wings": [], "htail": {},
		"vtails": [], "engines": [], "gear": {"type": "tricycle", "retract": false, "wheels": []},
		"cg": 0.28, "rates": {"ail": 22.0, "elev": 20.0, "rud": 25.0, "flap": 35.0},
		"servo_speed": 420.0, "strength": 1.0, "livery": {}, "labels": [],
		"batteries": [], "props": [], "tank": 0.0, "fuel_type": "", "gear_drag": 0.012,
		"body_cd": 0.12, "sound": "", "wheelbase_brake": 3.0, "details": {},
	}
	d.merge(o, true)
	return d

# ---------------------------------------------------------------- roster
static func _build() -> Array:
	var L: Array = []

	# 1 ── Trainer: Skylark 150 (foam, high wing, tricycle, electric 4S)
	L.append(_base({
		"id": "skylark", "name": "Skylark 150", "category": "Trainer",
		"blurb": "Forgiving high-wing foam trainer. Flat-bottom wing, flaps, gentle stall.",
		"material": "foam", "mass": 1.12, "length": 1.17,
		"fuselage": [[0.055, 0.040, 0.045, 0.0, 2.2], [0.10, 0.058, 0.065, 0.004, 2.5], [0.22, 0.064, 0.090, 0.018, 2.8],
			[0.38, 0.064, 0.100, 0.028, 2.9], [0.52, 0.058, 0.086, 0.028, 2.7], [0.72, 0.044, 0.062, 0.034, 2.4],
			[0.92, 0.030, 0.044, 0.040, 2.2], [1.10, 0.016, 0.030, 0.046, 2.1], [1.165, 0.006, 0.018, 0.048, 2.0]],
		"canopy": {"z0": 0.17, "z1": 0.43, "hw": 0.062, "hh": 0.058, "y": 0.07, "style": "cabin", "tint": Color(0.10, 0.14, 0.18)},
		"wings": [_wing(0.27, 0.125, 1.52, 0.255, 0.19, {"dihedral": 5.0, "incidence": 2.0, "washout": 1.5, "thick": 0.13,
			"camber": 0.035, "ail": [0.46, 0.94, 0.24], "flap": [0.07, 0.42, 0.25], "struts": true, "stall_deg": 14.5})],
		"htail": _htail(0.975, 0.045, 0.52, 0.15, 0.11, {"elev_cf": 0.42}),
		"vtails": [_vtail(0.935, 0.07, 0.19, 0.20, 0.10, {"sweep": 32.0, "rudder_cf": 0.45})],
		"engines": [_elec(Vector3(0, 0.0, 0.065), 680.0, 0.032, 1.3, 0.17, {"spinner_r": 0.028, "spinner_len": 0.055})],
		"gear": {"type": "tricycle", "retract": false, "wheels": [
			_wheel(0, -0.035, 0.12, 0.034, {"len": 0.12, "steer": true, "style": "wire", "brake": false}),
			_wheel(-0.15, -0.05, 0.37, 0.04, {"len": 0.11, "style": "spring", "pants": true}),
			_wheel(0.15, -0.05, 0.37, 0.04, {"len": 0.11, "style": "spring", "pants": true})]},
		"cg": 0.27, "rates": {"ail": 20.0, "elev": 18.0, "rud": 26.0, "flap": 35.0},
		"livery": {"scheme": "swoosh", "base": Color(0.95, 0.95, 0.96), "a1": Color(0.10, 0.30, 0.82), "a2": Color(0.12, 0.13, 0.16)},
		"labels": [{"text": "SKYLARK 150", "z": 0.62, "y": 0.02, "size": 0.035, "color": Color(0.1, 0.25, 0.7)}],
		"batteries": [_batt("4S 3200 mAh", 4, 3.2, 0.34), _batt("4S 4000 mAh", 4, 4.0, 0.42), _batt("3S 3200 mAh", 3, 3.2, 0.26)],
		"props": [_prop("11 x 7.5", 11, 7.5), _prop("12 x 6", 12, 6), _prop("10 x 8", 10, 8)],
		"body_cd": 0.18, "strength": 1.1,
	}))

	# 2 ── Bush: Tundra Cub (foam, strutted high wing, taildragger bush wheels)
	L.append(_base({
		"id": "tundra_cub", "name": "Tundra Cub", "category": "Bush / STOL",
		"blurb": "Light-wing-loading bush plane on fat tundra tires. Taildragger - use rudder on takeoff.",
		"material": "foam", "mass": 1.05, "length": 0.93,
		"fuselage": [[0.05, 0.048, 0.052, 0.005, 2.8], [0.10, 0.058, 0.070, 0.010, 3.2], [0.20, 0.060, 0.088, 0.022, 3.6],
			[0.34, 0.058, 0.092, 0.030, 3.6], [0.48, 0.050, 0.075, 0.034, 3.2], [0.66, 0.036, 0.052, 0.040, 2.8],
			[0.84, 0.020, 0.034, 0.046, 2.4], [0.92, 0.008, 0.022, 0.048, 2.2]],
		"canopy": {"z0": 0.15, "z1": 0.36, "hw": 0.059, "hh": 0.052, "y": 0.075, "style": "cabin", "tint": Color(0.10, 0.12, 0.14)},
		"wings": [_wing(0.21, 0.125, 1.30, 0.20, 0.20, {"dihedral": 2.0, "incidence": 2.5, "washout": 1.0, "thick": 0.135,
			"camber": 0.04, "ail": [0.5, 0.96, 0.24], "flap": [0.08, 0.46, 0.26], "struts": true, "tip_style": "square", "stall_deg": 15.0})],
		"htail": _htail(0.79, 0.05, 0.44, 0.13, 0.10, {"elev_cf": 0.45, "sweep": 4.0}),
		"vtails": [_vtail(0.76, 0.07, 0.17, 0.16, 0.10, {"sweep": 18.0, "rudder_cf": 0.5})],
		"engines": [_elec(Vector3(0, 0.005, 0.055), 900.0, 0.036, 1.1, 0.14, {"spinner_r": 0.024, "spinner_len": 0.045})],
		"gear": {"type": "taildragger", "retract": false, "wheels": [
			_wheel(-0.13, -0.10, 0.17, 0.065, {"len": 0.08, "style": "bush", "w": 0.05}),
			_wheel(0.13, -0.10, 0.17, 0.065, {"len": 0.08, "style": "bush", "w": 0.05}),
			_wheel(0, 0.005, 0.87, 0.018, {"len": 0.04, "steer": true, "style": "tail", "tail": true, "brake": false})]},
		"cg": 0.28, "rates": {"ail": 22.0, "elev": 22.0, "rud": 30.0, "flap": 40.0},
		"livery": {"scheme": "cub", "base": Color(0.98, 0.80, 0.08), "a1": Color(0.06, 0.06, 0.07), "a2": Color(0.85, 0.85, 0.85)},
		"labels": [{"text": "TUNDRA CUB", "z": 0.45, "y": 0.005, "size": 0.03, "color": Color(0.05, 0.05, 0.05)}],
		"batteries": [_batt("3S 2200 mAh", 3, 2.2, 0.19), _batt("4S 2200 mAh", 4, 2.2, 0.25)],
		"props": [_prop("11 x 5.5", 11, 5.5), _prop("10 x 6", 10, 6)],
		"body_cd": 0.28, "gear_drag": 0.03,
	}))

	# 3 ── STOL: Ridgeline STOL (foam, slats + big flaps)
	L.append(_base({
		"id": "ridgeline", "name": "Ridgeline STOL", "category": "Bush / STOL",
		"blurb": "Leading-edge slats and huge flaps. Lands in a few metres with a headwind.",
		"material": "foam", "mass": 1.30, "length": 1.10,
		"fuselage": [[0.055, 0.050, 0.055, 0.004, 2.8], [0.11, 0.062, 0.075, 0.010, 3.2], [0.22, 0.066, 0.095, 0.024, 3.5],
			[0.38, 0.064, 0.098, 0.032, 3.4], [0.54, 0.054, 0.080, 0.036, 3.0], [0.76, 0.038, 0.055, 0.042, 2.6],
			[0.98, 0.022, 0.036, 0.048, 2.3], [1.09, 0.008, 0.022, 0.050, 2.1]],
		"canopy": {"z0": 0.17, "z1": 0.40, "hw": 0.065, "hh": 0.056, "y": 0.08, "style": "cabin", "tint": Color(0.09, 0.11, 0.13)},
		"wings": [_wing(0.24, 0.135, 1.50, 0.23, 0.21, {"dihedral": 2.5, "incidence": 2.5, "washout": 1.0, "thick": 0.14,
			"camber": 0.045, "ail": [0.55, 0.96, 0.24], "flap": [0.07, 0.53, 0.30], "slats": true, "struts": true,
			"tip_style": "square", "stall_deg": 16.0})],
		"htail": _htail(0.93, 0.055, 0.55, 0.15, 0.12, {"elev_cf": 0.45}),
		"vtails": [_vtail(0.89, 0.075, 0.20, 0.19, 0.11, {"sweep": 22.0, "rudder_cf": 0.5})],
		"engines": [_elec(Vector3(0, 0.004, 0.06), 850.0, 0.030, 1.3, 0.18, {"spinner_r": 0.028, "spinner_len": 0.055})],
		"gear": {"type": "taildragger", "retract": false, "wheels": [
			_wheel(-0.15, -0.115, 0.20, 0.07, {"len": 0.09, "style": "bush", "w": 0.055, "k_scale": 0.9}),
			_wheel(0.15, -0.115, 0.20, 0.07, {"len": 0.09, "style": "bush", "w": 0.055, "k_scale": 0.9}),
			_wheel(0, 0.005, 1.03, 0.02, {"len": 0.045, "steer": true, "style": "tail", "tail": true, "brake": false})]},
		"cg": 0.27, "rates": {"ail": 22.0, "elev": 24.0, "rud": 30.0, "flap": 45.0},
		"livery": {"scheme": "stol", "base": Color(0.96, 0.96, 0.95), "a1": Color(1.0, 0.45, 0.05), "a2": Color(0.20, 0.22, 0.24)},
		"labels": [{"text": "RIDGELINE", "z": 0.52, "y": 0.01, "size": 0.034, "color": Color(0.2, 0.2, 0.22)}],
		"batteries": [_batt("4S 3000 mAh", 4, 3.0, 0.33), _batt("4S 3300 mAh", 4, 3.3, 0.36)],
		"props": [_prop("12 x 6", 12, 6, 3), _prop("11 x 7", 11, 7, 3)],
		"body_cd": 0.25, "gear_drag": 0.03,
	}))

	# 4 ── 3D aerobat: Vortex 540 (balsa/composite, 35cc gas)
	L.append(_base({
		"id": "vortex540", "name": "Vortex 540", "category": "Aerobatic",
		"blurb": "74\" gas-powered 3D monster. Symmetrical wing, huge surfaces, hovers on the prop.",
		"material": "film", "mass": 4.9, "length": 1.80,
		"fuselage": [[0.075, 0.075, 0.075, 0.0, 2.0], [0.16, 0.095, 0.10, 0.004, 2.2], [0.40, 0.10, 0.14, 0.010, 2.4],
			[0.62, 0.090, 0.14, 0.020, 2.4], [0.90, 0.070, 0.11, 0.030, 2.3], [1.25, 0.045, 0.075, 0.045, 2.2],
			[1.58, 0.024, 0.045, 0.055, 2.1], [1.78, 0.010, 0.028, 0.06, 2.0]],
		"canopy": {"z0": 0.62, "z1": 1.00, "hw": 0.065, "hh": 0.075, "y": 0.13, "style": "bubble", "tint": Color(0.08, 0.09, 0.11)},
		"wings": [_wing(0.42, -0.01, 1.90, 0.52, 0.28, {"dihedral": 0.0, "incidence": 0.0, "washout": 0.0, "thick": 0.14,
			"camber": 0.0, "ail": [0.10, 0.97, 0.30], "tip_style": "square", "stall_deg": 15.0, "sweep": 5.0})],
		"htail": _htail(1.52, 0.045, 0.74, 0.26, 0.17, {"elev_cf": 0.48, "thick": 0.07}),
		"vtails": [_vtail(1.45, 0.08, 0.36, 0.34, 0.20, {"sweep": 22.0, "rudder_cf": 0.62})],
		"engines": [_ic("gas2", Vector3(0, 0.0, 0.075), 3.9, 7200.0, 8400.0, 1.1, {"spinner_r": 0.045, "spinner_len": 0.085})],
		"gear": {"type": "taildragger", "retract": false, "wheels": [
			_wheel(-0.19, -0.19, 0.36, 0.055, {"len": 0.14, "style": "spring", "pants": true, "w": 0.03}),
			_wheel(0.19, -0.19, 0.36, 0.055, {"len": 0.14, "style": "spring", "pants": true, "w": 0.03}),
			_wheel(0, 0.02, 1.72, 0.022, {"len": 0.05, "steer": true, "style": "tail", "tail": true, "brake": false})]},
		"cg": 0.30, "rates": {"ail": 34.0, "elev": 38.0, "rud": 40.0, "flap": 0.0},
		"livery": {"scheme": "sunburst", "base": Color(0.97, 0.97, 0.97), "a1": Color(0.85, 0.06, 0.08), "a2": Color(0.08, 0.08, 0.09)},
		"labels": [{"text": "VORTEX 540", "z": 1.05, "y": 0.02, "size": 0.06, "color": Color(0.08, 0.08, 0.09)}],
		"props": [_prop("20 x 8", 20, 8), _prop("21 x 10", 21, 10), _prop("20 x 10", 20, 10)],
		"tank": 0.55, "fuel_type": "Gasoline", "body_cd": 0.14, "strength": 1.6, "servo_speed": 520.0,
	}))

	# 5 ── Aerobatic: Aerostar 330 (balsa, glow 2-stroke)
	L.append(_base({
		"id": "aerostar", "name": "Aerostar 330", "category": "Aerobatic",
		"blurb": "Classic .91 glow pattern/aerobatic plane. Crisp, precise, screaming two-stroke.",
		"material": "film", "mass": 3.1, "length": 1.45,
		"fuselage": [[0.065, 0.06, 0.06, 0.0, 2.0], [0.13, 0.075, 0.08, 0.004, 2.2], [0.32, 0.08, 0.11, 0.008, 2.4],
			[0.52, 0.074, 0.11, 0.018, 2.4], [0.78, 0.058, 0.085, 0.028, 2.3], [1.05, 0.038, 0.06, 0.040, 2.2],
			[1.30, 0.02, 0.036, 0.048, 2.1], [1.44, 0.008, 0.02, 0.05, 2.0]],
		"canopy": {"z0": 0.50, "z1": 0.84, "hw": 0.056, "hh": 0.064, "y": 0.10, "style": "bubble", "tint": Color(0.10, 0.12, 0.15)},
		"wings": [_wing(0.34, -0.012, 1.62, 0.42, 0.24, {"dihedral": 0.5, "incidence": 0.0, "washout": 0.0, "thick": 0.14,
			"camber": 0.0, "ail": [0.12, 0.96, 0.26], "tip_style": "square", "sweep": 4.0})],
		"htail": _htail(1.23, 0.035, 0.60, 0.20, 0.13, {"elev_cf": 0.42}),
		"vtails": [_vtail(1.17, 0.06, 0.28, 0.26, 0.15, {"sweep": 24.0, "rudder_cf": 0.5})],
		"engines": [_ic("glow2", Vector3(0, 0.0, 0.065), 1.45, 11500.0, 13500.0, 0.62, {"spinner_r": 0.037, "spinner_len": 0.07})],
		"gear": {"type": "taildragger", "retract": false, "wheels": [
			_wheel(-0.16, -0.16, 0.30, 0.042, {"len": 0.12, "style": "spring", "pants": true}),
			_wheel(0.16, -0.16, 0.30, 0.042, {"len": 0.12, "style": "spring", "pants": true}),
			_wheel(0, 0.015, 1.39, 0.018, {"len": 0.04, "steer": true, "style": "tail", "tail": true, "brake": false})]},
		"cg": 0.29, "rates": {"ail": 26.0, "elev": 26.0, "rud": 32.0, "flap": 0.0},
		"livery": {"scheme": "aerostar", "base": Color(0.96, 0.96, 0.97), "a1": Color(0.10, 0.22, 0.62), "a2": Color(0.86, 0.10, 0.10)},
		"labels": [{"text": "AEROSTAR", "z": 0.95, "y": 0.02, "size": 0.05, "color": Color(0.10, 0.22, 0.62)}],
		"props": [_prop("15 x 8", 15, 8), _prop("16 x 7", 16, 7)],
		"tank": 0.40, "fuel_type": "Glow (15% nitro)", "body_cd": 0.14, "strength": 1.2,
	}))

	# 6 ── Biplane: Skipper Bipe (fabric, glow 4-stroke)
	L.append(_base({
		"id": "skipper", "name": "Skipper Bipe", "category": "Biplane",
		"blurb": "Stubby aerobatic biplane with a thumping four-stroke. Snaps like a whip.",
		"material": "fabric", "mass": 2.75, "length": 1.08,
		"fuselage": [[0.06, 0.07, 0.07, 0.0, 2.0], [0.11, 0.085, 0.09, 0.0, 2.1], [0.26, 0.085, 0.11, 0.01, 2.4],
			[0.42, 0.075, 0.105, 0.02, 2.4], [0.62, 0.058, 0.08, 0.028, 2.3], [0.86, 0.034, 0.05, 0.036, 2.2],
			[1.06, 0.01, 0.024, 0.04, 2.0]],
		"canopy": {"z0": 0.40, "z1": 0.56, "hw": 0.045, "hh": 0.045, "y": 0.095, "style": "open", "tint": Color(0.3, 0.35, 0.4)},
		"wings": [
			_wing(0.20, 0.20, 1.20, 0.25, 0.22, {"dihedral": 1.5, "incidence": 0.5, "washout": 0.0, "thick": 0.13,
				"camber": 0.0, "ail": [0.18, 0.96, 0.27], "tip_style": "round", "sweep": 9.0, "x0": 0.0}),
			_wing(0.30, -0.075, 1.12, 0.23, 0.20, {"dihedral": 3.0, "incidence": 0.5, "washout": 0.0, "thick": 0.13,
				"camber": 0.0, "ail": [0.18, 0.96, 0.27], "tip_style": "round", "sweep": 0.0})],
		"htail": _htail(0.90, 0.03, 0.44, 0.15, 0.10, {"elev_cf": 0.45}),
		"vtails": [_vtail(0.86, 0.05, 0.19, 0.20, 0.12, {"sweep": 30.0, "rudder_cf": 0.55})],
		"engines": [_ic("glow4", Vector3(0, 0.0, 0.06), 1.55, 9500.0, 11200.0, 0.64, {"spinner_r": 0.034, "spinner_len": 0.06})],
		"gear": {"type": "taildragger", "retract": false, "wheels": [
			_wheel(-0.13, -0.155, 0.18, 0.042, {"len": 0.12, "style": "strut", "pants": true}),
			_wheel(0.13, -0.155, 0.18, 0.042, {"len": 0.12, "style": "strut", "pants": true}),
			_wheel(0, 0.012, 1.02, 0.017, {"len": 0.035, "steer": true, "style": "tail", "tail": true, "brake": false})]},
		"cg": 0.28, "rates": {"ail": 24.0, "elev": 26.0, "rud": 32.0, "flap": 0.0},
		"livery": {"scheme": "bipe", "base": Color(0.96, 0.95, 0.92), "a1": Color(0.80, 0.07, 0.07), "a2": Color(0.08, 0.08, 0.1)},
		"labels": [{"text": "SKIPPER", "z": 0.66, "y": 0.0, "size": 0.035, "color": Color(0.8, 0.07, 0.07)}],
		"props": [_prop("14 x 6", 14, 6), _prop("15 x 6", 15, 6)],
		"tank": 0.35, "fuel_type": "Glow (15% nitro)", "body_cd": 0.20, "gear_drag": 0.02, "strength": 1.0,
	}))

	# 7 ── Warbird: Silver Belle P-51 style (glow 4-stroke, retracts, metal finish)
	L.append(_base({
		"id": "belle51", "name": "Silver Belle 51", "category": "Warbird",
		"blurb": "P-51-style warbird in polished-metal finish. Retracts, big 4-blade prop, torque roll.",
		"material": "metal", "mass": 4.1, "length": 1.42,
		"fuselage": [[0.08, 0.055, 0.062, 0.012, 2.0], [0.15, 0.072, 0.09, 0.008, 2.2], [0.35, 0.078, 0.11, 0.0, 2.2],
			[0.55, 0.076, 0.13, -0.012, 2.3], [0.70, 0.07, 0.13, -0.020, 2.3], [0.88, 0.055, 0.10, 0.0, 2.2],
			[1.10, 0.036, 0.075, 0.02, 2.1], [1.30, 0.018, 0.05, 0.035, 2.0], [1.41, 0.006, 0.03, 0.04, 2.0]],
		"canopy": {"z0": 0.50, "z1": 0.82, "hw": 0.052, "hh": 0.068, "y": 0.085, "style": "bubble", "tint": Color(0.10, 0.12, 0.14)},
		"wings": [_wing(0.40, -0.06, 1.62, 0.40, 0.19, {"dihedral": 5.0, "incidence": 1.0, "washout": 1.5, "thick": 0.14,
			"camber": 0.02, "ail": [0.55, 0.93, 0.22], "flap": [0.07, 0.52, 0.2], "tip_style": "square", "sweep": 2.0, "stall_deg": 14.0})],
		"htail": _htail(1.21, 0.045, 0.52, 0.18, 0.10, {"elev_cf": 0.38}),
		"vtails": [_vtail(1.14, 0.06, 0.22, 0.26, 0.10, {"sweep": 25.0, "rudder_cf": 0.4})],
		"engines": [_ic("glow4", Vector3(0, 0.012, 0.08), 2.9, 8200.0, 9800.0, 1.0, {"spinner_r": 0.05, "spinner_len": 0.10})],
		"gear": {"type": "taildragger", "retract": true, "wheels": [
			_wheel(-0.17, -0.19, 0.38, 0.05, {"len": 0.13, "style": "oleo", "w": 0.024}),
			_wheel(0.17, -0.19, 0.38, 0.05, {"len": 0.13, "style": "oleo", "w": 0.024}),
			_wheel(0, -0.01, 1.28, 0.02, {"len": 0.05, "steer": true, "style": "tail", "tail": true, "brake": false})]},
		"cg": 0.27, "rates": {"ail": 18.0, "elev": 18.0, "rud": 22.0, "flap": 35.0},
		"livery": {"scheme": "p51", "base": Color(0.78, 0.80, 0.82), "a1": Color(0.85, 0.08, 0.06), "a2": Color(0.98, 0.84, 0.06), "a3": Color(0.20, 0.22, 0.12)},
		"labels": [{"text": "SILVER BELLE", "z": 0.34, "y": 0.02, "size": 0.03, "color": Color(0.85, 0.08, 0.06)},
			{"text": "RC-51", "z": 1.18, "y": 0.10, "size": 0.035, "color": Color(0.05, 0.05, 0.05), "vtail": true}],
		"props": [_prop("16 x 10 (4-blade)", 16, 10, 4), _prop("18 x 8 (3-blade)", 18, 8, 3)],
		"tank": 0.45, "fuel_type": "Glow (15% nitro)", "body_cd": 0.11, "gear_drag": 0.02, "strength": 1.3,
		"details": {"scoop": true, "exhaust_stacks": 6},
	}))

	# 8 ── Sport low-wing: Valor 46 (balsa, glow 2-stroke, tricycle)
	L.append(_base({
		"id": "valor", "name": "Valor 46", "category": "Sport Trainer",
		"blurb": "Low-wing balsa sport trainer - the step up from high-wings. Honest .46 two-stroke.",
		"material": "film", "mass": 2.45, "length": 1.30,
		"fuselage": [[0.06, 0.05, 0.05, 0.0, 2.2], [0.12, 0.065, 0.07, 0.004, 2.6], [0.30, 0.07, 0.095, 0.012, 2.8],
			[0.48, 0.066, 0.095, 0.022, 2.8], [0.72, 0.05, 0.07, 0.03, 2.5], [0.98, 0.034, 0.05, 0.04, 2.3],
			[1.22, 0.018, 0.032, 0.046, 2.1], [1.29, 0.008, 0.02, 0.048, 2.0]],
		"canopy": {"z0": 0.36, "z1": 0.64, "hw": 0.052, "hh": 0.055, "y": 0.09, "style": "bubble", "tint": Color(0.1, 0.13, 0.16)},
		"wings": [_wing(0.30, -0.045, 1.55, 0.30, 0.22, {"dihedral": 3.5, "incidence": 1.0, "washout": 1.0, "thick": 0.14,
			"camber": 0.02, "ail": [0.45, 0.94, 0.24], "flap": [0.06, 0.42, 0.24], "tip_style": "round"})],
		"htail": _htail(1.07, 0.035, 0.56, 0.16, 0.11, {"elev_cf": 0.42}),
		"vtails": [_vtail(1.03, 0.05, 0.21, 0.22, 0.11, {"sweep": 30.0, "rudder_cf": 0.45})],
		"engines": [_ic("glow2", Vector3(0, 0.0, 0.06), 0.72, 12500.0, 15000.0, 0.40, {"spinner_r": 0.03, "spinner_len": 0.06})],
		"gear": {"type": "tricycle", "retract": false, "wheels": [
			_wheel(0, -0.095, 0.13, 0.035, {"len": 0.13, "steer": true, "style": "wire", "brake": false}),
			_wheel(-0.17, -0.10, 0.42, 0.04, {"len": 0.10, "style": "wire", "pants": false}),
			_wheel(0.17, -0.10, 0.42, 0.04, {"len": 0.10, "style": "wire", "pants": false})]},
		"cg": 0.28, "rates": {"ail": 20.0, "elev": 18.0, "rud": 25.0, "flap": 30.0},
		"livery": {"scheme": "valor", "base": Color(0.98, 0.98, 0.98), "a1": Color(0.05, 0.55, 0.30), "a2": Color(0.98, 0.72, 0.05)},
		"labels": [{"text": "VALOR 46", "z": 0.80, "y": 0.02, "size": 0.04, "color": Color(0.05, 0.45, 0.25)}],
		"props": [_prop("11 x 6", 11, 6), _prop("12 x 6", 12, 6)],
		"tank": 0.30, "fuel_type": "Glow (15% nitro)", "body_cd": 0.16, "gear_drag": 0.02,
	}))

	# 9 ── Warbird trainer: Tiger 28 (foam, electric 6S, radial cowl, 3 blades, retracts)
	L.append(_base({
		"id": "tiger28", "name": "Tiger 28", "category": "Warbird",
		"blurb": "Big-radial warbird trainer in foam. Tricycle retracts, 6S, stable and heavy.",
		"material": "painted", "mass": 2.7, "length": 1.22,
		"fuselage": [[0.07, 0.085, 0.085, 0.0, 2.0], [0.14, 0.092, 0.095, 0.0, 2.0], [0.28, 0.085, 0.105, 0.008, 2.2],
			[0.48, 0.075, 0.105, 0.018, 2.3], [0.72, 0.056, 0.08, 0.03, 2.2], [0.96, 0.036, 0.056, 0.04, 2.1],
			[1.16, 0.016, 0.035, 0.05, 2.0], [1.21, 0.008, 0.024, 0.052, 2.0]],
		"canopy": {"z0": 0.30, "z1": 0.72, "hw": 0.052, "hh": 0.07, "y": 0.09, "style": "bubble", "tint": Color(0.1, 0.12, 0.15)},
		"wings": [_wing(0.30, -0.05, 1.40, 0.32, 0.17, {"dihedral": 6.0, "incidence": 1.0, "washout": 1.5, "thick": 0.14,
			"camber": 0.02, "ail": [0.52, 0.92, 0.22], "flap": [0.07, 0.48, 0.22], "tip_style": "square"})],
		"htail": _htail(1.00, 0.045, 0.52, 0.17, 0.10, {"elev_cf": 0.4}),
		"vtails": [_vtail(0.96, 0.06, 0.24, 0.24, 0.10, {"sweep": 12.0, "rudder_cf": 0.42})],
		"engines": [_elec(Vector3(0, 0.0, 0.07), 520.0, 0.022, 1.6, 0.30, {"spinner_r": 0.035, "spinner_len": 0.07, "radial": true})],
		"gear": {"type": "tricycle", "retract": true, "wheels": [
			_wheel(0, -0.145, 0.20, 0.038, {"len": 0.12, "steer": true, "style": "oleo", "brake": false}),
			_wheel(-0.19, -0.13, 0.42, 0.045, {"len": 0.12, "style": "oleo"}),
			_wheel(0.19, -0.13, 0.42, 0.045, {"len": 0.12, "style": "oleo"})]},
		"cg": 0.27, "rates": {"ail": 18.0, "elev": 18.0, "rud": 22.0, "flap": 35.0},
		"livery": {"scheme": "t28", "base": Color(0.10, 0.20, 0.45), "a1": Color(0.98, 0.78, 0.10), "a2": Color(0.95, 0.95, 0.95)},
		"labels": [{"text": "TIGER 28", "z": 0.80, "y": 0.02, "size": 0.04, "color": Color(0.98, 0.78, 0.1)}],
		"batteries": [_batt("6S 4000 mAh", 6, 4.0, 0.62), _batt("6S 5000 mAh", 6, 5.0, 0.76), _batt("5S 4000 mAh", 5, 4.0, 0.52)],
		"props": [_prop("14 x 8.5 (3-blade)", 14, 8.5, 3), _prop("14 x 7 (3-blade)", 14, 7, 3)],
		"body_cd": 0.24, "gear_drag": 0.02,
	}))

	# 10 ── EDF sport jet: Viper 90 (foam, 90 mm EDF, side intakes)
	L.append(_base({
		"id": "viper90", "name": "Viper 90 EDF", "category": "EDF Jet",
		"blurb": "90 mm 6S ducted-fan sport jet. Fast, smooth, needs speed on approach.",
		"material": "foam", "mass": 2.1, "length": 1.30,
		"fuselage": [[0.0, 0.004, 0.004, 0.0, 2.0], [0.12, 0.045, 0.05, 0.0, 2.0], [0.30, 0.075, 0.085, 0.008, 2.2],
			[0.50, 0.085, 0.095, 0.012, 2.4], [0.75, 0.080, 0.085, 0.01, 2.4], [1.00, 0.068, 0.07, 0.008, 2.2],
			[1.22, 0.058, 0.058, 0.006, 2.0], [1.30, 0.056, 0.056, 0.006, 2.0]],
		"canopy": {"z0": 0.25, "z1": 0.62, "hw": 0.055, "hh": 0.068, "y": 0.07, "style": "jet", "tint": Color(0.18, 0.12, 0.08)},
		"wings": [_wing(0.62, -0.02, 1.15, 0.40, 0.14, {"dihedral": -1.0, "incidence": 1.0, "washout": 0.5, "thick": 0.10,
			"camber": 0.01, "ail": [0.50, 0.92, 0.25], "flap": [0.10, 0.48, 0.25], "sweep": 30.0, "tip_style": "square", "stall_deg": 16.0})],
		"htail": _htail(1.13, 0.03, 0.46, 0.18, 0.07, {"sweep": 35.0, "elev_cf": 0.4}),
		"vtails": [_vtail(1.02, 0.07, 0.24, 0.30, 0.09, {"sweep": 45.0, "rudder_cf": 0.35})],
		"engines": [_edf(Vector3(0, 0.005, 0.95), 90.0, 38.0, 72.0, 95.0, 0.55, {"intake": "sides", "intake_z": 0.46})],
		"gear": {"type": "tricycle", "retract": true, "wheels": [
			_wheel(0, -0.12, 0.30, 0.03, {"len": 0.12, "steer": true, "style": "oleo", "brake": false}),
			_wheel(-0.14, -0.10, 0.80, 0.035, {"len": 0.10, "style": "oleo"}),
			_wheel(0.14, -0.10, 0.80, 0.035, {"len": 0.10, "style": "oleo"})]},
		"cg": 0.20, "rates": {"ail": 16.0, "elev": 16.0, "rud": 20.0, "flap": 35.0},
		"livery": {"scheme": "viper", "base": Color(0.97, 0.97, 0.97), "a1": Color(0.88, 0.08, 0.06), "a2": Color(0.18, 0.19, 0.21)},
		"labels": [{"text": "VIPER", "z": 0.36, "y": -0.01, "size": 0.05, "color": Color(0.18, 0.19, 0.21)},
			{"text": "90", "z": 1.20, "y": 0.16, "size": 0.06, "color": Color(0.97, 0.97, 0.97), "vtail": true}],
		"batteries": [_batt("6S 5000 mAh", 6, 5.0, 0.72), _batt("6S 6000 mAh", 6, 6.0, 0.86)],
		"body_cd": 0.09, "gear_drag": 0.02, "strength": 1.0,
	}))

	# 11 ── Turbine jet: Striker 16 (F-16 style, composite, turbine, stabilators)
	L.append(_base({
		"id": "striker16", "name": "Striker 16", "category": "Turbine Jet",
		"blurb": "F-16-style 1:6 composite jet with a 100 N turbine. Tailerons, slow spool, serious speed.",
		"material": "painted", "mass": 10.5, "length": 2.40,
		"fuselage": [[0.0, 0.005, 0.005, 0.0, 2.0], [0.20, 0.06, 0.065, 0.0, 2.0], [0.50, 0.10, 0.11, 0.01, 2.2],
			[0.85, 0.13, 0.13, 0.0, 2.6], [1.30, 0.13, 0.12, 0.0, 2.8], [1.80, 0.11, 0.10, 0.0, 2.4],
			[2.20, 0.075, 0.075, 0.0, 2.0], [2.40, 0.065, 0.065, 0.0, 2.0]],
		"canopy": {"z0": 0.38, "z1": 0.95, "hw": 0.07, "hh": 0.10, "y": 0.09, "style": "jet", "tint": Color(0.35, 0.25, 0.08)},
		"wings": [_wing(1.05, 0.0, 1.50, 0.85, 0.20, {"dihedral": 0.0, "incidence": 0.0, "washout": 0.0, "thick": 0.05,
			"camber": 0.0, "ail": [0.20, 0.62, 0.25], "flap": [], "sweep": 40.0, "tip_style": "rail", "stall_deg": 22.0})],
		"htail": _htail(1.95, -0.01, 0.95, 0.40, 0.14, {"sweep": 40.0, "stabilator": true, "taileron": 0.5, "dihedral": -10.0, "thick": 0.05}),
		"vtails": [_vtail(1.70, 0.10, 0.52, 0.55, 0.18, {"sweep": 47.0, "rudder_cf": 0.3})],
		"engines": [_turbine(Vector3(0, 0.0, 2.2), 100.0, 1.1, {"intake": "belly", "intake_z": 0.75, "fan_d": 0.13})],
		"gear": {"type": "tricycle", "retract": true, "wheels": [
			_wheel(0, -0.22, 0.62, 0.045, {"len": 0.16, "steer": true, "style": "oleo", "brake": false}),
			_wheel(-0.19, -0.2, 1.42, 0.06, {"len": 0.14, "style": "oleo"}),
			_wheel(0.19, -0.2, 1.42, 0.06, {"len": 0.14, "style": "oleo"})]},
		"cg": 0.25, "rates": {"ail": 15.0, "elev": 14.0, "rud": 18.0, "flap": 0.0},
		"livery": {"scheme": "grey2", "base": Color(0.56, 0.58, 0.60), "a1": Color(0.40, 0.42, 0.45), "a2": Color(0.2, 0.2, 0.22)},
		"labels": [{"text": "SW 520", "z": 1.95, "y": 0.35, "size": 0.07, "color": Color(0.12, 0.12, 0.13), "vtail": true}],
		"tank": 2.8, "fuel_type": "Kerosene", "body_cd": 0.07, "gear_drag": 0.02, "strength": 1.8, "servo_speed": 380.0,
	}))

	# 12 ── EDF: Specter 22 (F-22 style twin 70 mm)
	L.append(_base({
		"id": "specter22", "name": "Specter 22", "category": "EDF Jet",
		"blurb": "Twin 70 mm stealth-style jet. Canted twin tails, all-moving stabs, big alpha.",
		"material": "painted", "mass": 2.3, "length": 1.20,
		"fuselage": [[0.0, 0.004, 0.004, 0.0, 2.0], [0.12, 0.05, 0.035, 0.0, 3.0], [0.30, 0.09, 0.055, 0.0, 3.5],
			[0.50, 0.13, 0.06, 0.0, 4.0], [0.80, 0.14, 0.055, 0.0, 4.0], [1.05, 0.12, 0.045, 0.0, 3.5],
			[1.20, 0.10, 0.035, 0.0, 3.0]],
		"canopy": {"z0": 0.17, "z1": 0.46, "hw": 0.045, "hh": 0.055, "y": 0.03, "style": "jet", "tint": Color(0.40, 0.30, 0.08)},
		"wings": [_wing(0.52, 0.0, 0.88, 0.62, 0.10, {"dihedral": -2.0, "incidence": 0.0, "washout": 0.0, "thick": 0.05,
			"camber": 0.0, "ail": [0.35, 0.92, 0.22], "flap": [0.12, 0.35, 0.22], "sweep": 42.0, "tip_style": "square", "x0": 0.12, "stall_deg": 24.0})],
		"htail": _htail(1.03, 0.0, 0.62, 0.22, 0.08, {"sweep": 42.0, "stabilator": true, "taileron": 0.4, "thick": 0.05}),
		"vtails": [_vtail(0.88, 0.045, 0.19, 0.22, 0.08, {"x": 0.11, "sweep": 42.0, "rudder_cf": 0.3, "cant": 28.0, "mirror": true})],
		"engines": [_edf(Vector3(-0.055, 0.0, 1.15), 70.0, 18.0, 62.0, 60.0, 0.30, {"intake": "sides_single", "intake_z": 0.34}),
			_edf(Vector3(0.055, 0.0, 1.15), 70.0, 18.0, 62.0, 60.0, 0.30, {"intake": "sides_single", "intake_z": 0.34, "spin": -1})],
		"gear": {"type": "tricycle", "retract": true, "wheels": [
			_wheel(0, -0.12, 0.25, 0.028, {"len": 0.10, "steer": true, "style": "oleo", "brake": false}),
			_wheel(-0.12, -0.11, 0.72, 0.032, {"len": 0.10, "style": "oleo"}),
			_wheel(0.12, -0.11, 0.72, 0.032, {"len": 0.10, "style": "oleo"})]},
		"cg": 0.24, "rates": {"ail": 12.0, "elev": 18.0, "rud": 22.0, "flap": 30.0},
		"livery": {"scheme": "camo_grey", "base": Color(0.58, 0.60, 0.62), "a1": Color(0.44, 0.46, 0.49), "a2": Color(0.28, 0.29, 0.31)},
		"labels": [{"text": "FF", "z": 0.97, "y": 0.13, "size": 0.05, "color": Color(0.2, 0.2, 0.22), "vtail": true}],
		"batteries": [_batt("6S 5000 mAh", 6, 5.0, 0.72), _batt("6S 4000 mAh", 6, 4.0, 0.60)],
		"body_cd": 0.08, "gear_drag": 0.02,
	}))

	# 13 ── Attack jet: Brute 10 (A-10 style twin EDF pods, twin tails)
	L.append(_base({
		"id": "brute10", "name": "Brute 10", "category": "EDF Jet",
		"blurb": "Straight-wing ground-attack twin. Slow, stable, pods high on the tail. Tough as nails.",
		"material": "painted", "mass": 3.0, "length": 1.30,
		"fuselage": [[0.0, 0.01, 0.01, 0.0, 2.0], [0.08, 0.05, 0.055, 0.0, 2.0], [0.25, 0.075, 0.09, 0.005, 2.3],
			[0.50, 0.08, 0.10, 0.01, 2.6], [0.80, 0.07, 0.085, 0.02, 2.5], [1.05, 0.045, 0.055, 0.03, 2.3],
			[1.26, 0.022, 0.03, 0.04, 2.0], [1.30, 0.012, 0.02, 0.04, 2.0]],
		"canopy": {"z0": 0.14, "z1": 0.40, "hw": 0.05, "hh": 0.06, "y": 0.075, "style": "bubble", "tint": Color(0.12, 0.14, 0.16)},
		"wings": [_wing(0.50, -0.06, 1.45, 0.30, 0.18, {"dihedral": 3.0, "incidence": 1.5, "washout": 1.0, "thick": 0.15,
			"camber": 0.03, "ail": [0.62, 0.95, 0.25], "flap": [0.10, 0.58, 0.25], "tip_style": "droop", "stall_deg": 15.0})],
		"htail": _htail(1.12, 0.05, 0.56, 0.17, 0.17, {"elev_cf": 0.42, "sweep": 0.0}),
		"vtails": [_vtail(1.10, 0.05, 0.20, 0.19, 0.13, {"x": 0.28, "sweep": 8.0, "rudder_cf": 0.4, "mirror": true})],
		"engines": [_edf(Vector3(-0.11, 0.15, 0.86), 70.0, 16.0, 45.0, 55.0, 0.30, {"intake": "pod", "nacelle": {"len": 0.30, "r": 0.055}}),
			_edf(Vector3(0.11, 0.15, 0.86), 70.0, 16.0, 45.0, 55.0, 0.30, {"intake": "pod", "nacelle": {"len": 0.30, "r": 0.055}, "spin": -1})],
		"gear": {"type": "tricycle", "retract": false, "wheels": [
			_wheel(0.03, -0.13, 0.20, 0.032, {"len": 0.10, "steer": true, "style": "oleo", "brake": false}),
			_wheel(-0.30, -0.14, 0.55, 0.038, {"len": 0.08, "style": "oleo"}),
			_wheel(0.30, -0.14, 0.55, 0.038, {"len": 0.08, "style": "oleo"})]},
		"cg": 0.26, "rates": {"ail": 20.0, "elev": 18.0, "rud": 24.0, "flap": 35.0},
		"livery": {"scheme": "hog", "base": Color(0.54, 0.56, 0.57), "a1": Color(0.40, 0.42, 0.43), "a2": Color(0.85, 0.10, 0.10)},
		"labels": [{"text": "FT 104", "z": 1.16, "y": 0.13, "size": 0.045, "color": Color(0.12, 0.12, 0.13), "vtail": true}],
		"batteries": [_batt("6S 5000 mAh", 6, 5.0, 0.72), _batt("6S 4000 mAh", 6, 4.0, 0.60)],
		"body_cd": 0.14, "gear_drag": 0.03, "strength": 1.6,
		"details": {"sharkmouth": true, "gun": true},
	}))

	# 14 ── Multi-engine: Cargomaster 130 (C-130 style, 4 electric props)
	L.append(_base({
		"id": "cargo130", "name": "Cargomaster 130", "category": "Multi-engine",
		"blurb": "Four-engine tactical transport. Huge high wing, props wash the flaps, lumbering and loud.",
		"material": "painted", "mass": 4.0, "length": 1.60,
		"fuselage": [[0.0, 0.03, 0.03, 0.0, 2.0], [0.07, 0.085, 0.085, -0.005, 2.1], [0.20, 0.115, 0.12, 0.0, 2.6],
			[0.45, 0.12, 0.13, 0.0, 3.0], [0.95, 0.12, 0.13, 0.0, 3.0], [1.15, 0.10, 0.11, 0.035, 2.7],
			[1.38, 0.06, 0.07, 0.08, 2.3], [1.56, 0.022, 0.03, 0.11, 2.0], [1.60, 0.012, 0.018, 0.11, 2.0]],
		"canopy": {"z0": 0.05, "z1": 0.16, "hw": 0.085, "hh": 0.05, "y": 0.06, "style": "cockpit", "tint": Color(0.08, 0.1, 0.12)},
		"wings": [_wing(0.52, 0.125, 2.05, 0.30, 0.17, {"dihedral": 1.5, "incidence": 2.0, "washout": 1.5, "thick": 0.15,
			"camber": 0.035, "ail": [0.60, 0.95, 0.22], "flap": [0.07, 0.58, 0.25], "tip_style": "round", "stall_deg": 14.5})],
		"htail": _htail(1.40, 0.10, 0.80, 0.22, 0.13, {"elev_cf": 0.38, "sweep": 6.0}),
		"vtails": [_vtail(1.32, 0.13, 0.36, 0.33, 0.16, {"sweep": 20.0, "rudder_cf": 0.38})],
		"engines": [
			_elec(Vector3(-0.60, 0.11, 0.44), 780.0, 0.045, 0.9, 0.12, {"spinner_r": 0.025, "spinner_len": 0.05, "nacelle": {"len": 0.28, "r": 0.04}}),
			_elec(Vector3(-0.33, 0.11, 0.42), 780.0, 0.045, 0.9, 0.12, {"spinner_r": 0.025, "spinner_len": 0.05, "nacelle": {"len": 0.30, "r": 0.04}}),
			_elec(Vector3(0.33, 0.11, 0.42), 780.0, 0.045, 0.9, 0.12, {"spinner_r": 0.025, "spinner_len": 0.05, "nacelle": {"len": 0.30, "r": 0.04}}),
			_elec(Vector3(0.60, 0.11, 0.44), 780.0, 0.045, 0.9, 0.12, {"spinner_r": 0.025, "spinner_len": 0.05, "nacelle": {"len": 0.28, "r": 0.04}})],
		"gear": {"type": "tricycle", "retract": false, "wheels": [
			_wheel(0, -0.15, 0.20, 0.035, {"len": 0.06, "steer": true, "style": "oleo", "brake": false}),
			_wheel(-0.13, -0.15, 0.72, 0.045, {"len": 0.06, "style": "pod"}),
			_wheel(0.13, -0.15, 0.72, 0.045, {"len": 0.06, "style": "pod"})]},
		"cg": 0.25, "rates": {"ail": 20.0, "elev": 18.0, "rud": 24.0, "flap": 35.0},
		"livery": {"scheme": "cargo", "base": Color(0.55, 0.57, 0.58), "a1": Color(0.1, 0.1, 0.11), "a2": Color(0.2, 0.3, 0.6)},
		"labels": [{"text": "CARGOMASTER", "z": 0.30, "y": 0.06, "size": 0.035, "color": Color(0.12, 0.12, 0.13)},
			{"text": "7315", "z": 1.45, "y": 0.28, "size": 0.05, "color": Color(0.12, 0.12, 0.13), "vtail": true}],
		"batteries": [_batt("2x 4S 4000 mAh (parallel)", 4, 8.0, 0.86), _batt("2x 4S 5000 mAh (parallel)", 4, 10.0, 1.02)],
		"props": [_prop("9 x 6 (4-blade)", 9, 6, 4), _prop("10 x 5 (3-blade)", 10, 5, 3)],
		"body_cd": 0.20, "gear_drag": 0.015, "strength": 1.2,
	}))

	# 15 ── Airliner: Skyliner 74 (747 style, 4 x 50 mm EDF)
	L.append(_base({
		"id": "skyliner", "name": "Skyliner 74", "category": "Airliner",
		"blurb": "Jumbo-style four-engine airliner. Swept wing, upper deck hump, 18 wheels. Fly it like a big jet.",
		"material": "composite", "mass": 4.9, "length": 1.90,
		"fuselage": [[0.0, 0.01, 0.01, -0.01, 2.0], [0.06, 0.065, 0.07, -0.005, 2.0], [0.18, 0.095, 0.12, 0.018, 2.0],
			[0.40, 0.105, 0.14, 0.02, 2.0], [0.62, 0.105, 0.12, 0.0, 2.0], [1.30, 0.105, 0.11, 0.0, 2.0],
			[1.58, 0.075, 0.08, 0.02, 2.0], [1.80, 0.035, 0.045, 0.04, 2.0], [1.90, 0.012, 0.02, 0.045, 2.0]],
		"canopy": {"z0": 0.09, "z1": 0.16, "hw": 0.06, "hh": 0.03, "y": 0.105, "style": "cockpit", "tint": Color(0.05, 0.06, 0.08)},
		"wings": [_wing(0.72, -0.07, 1.95, 0.52, 0.12, {"dihedral": 6.0, "incidence": 2.0, "washout": 2.0, "thick": 0.11,
			"camber": 0.025, "ail": [0.62, 0.92, 0.22], "flap": [0.08, 0.58, 0.24], "sweep": 37.0, "tip_style": "winglet", "stall_deg": 15.0})],
		"htail": _htail(1.62, 0.04, 0.75, 0.24, 0.09, {"sweep": 36.0, "elev_cf": 0.33, "dihedral": 7.0}),
		"vtails": [_vtail(1.48, 0.10, 0.38, 0.38, 0.13, {"sweep": 45.0, "rudder_cf": 0.33})],
		"engines": [
			_edf(Vector3(-0.60, -0.14, 0.78), 50.0, 11.0, 42.0, 30.0, 0.13, {"intake": "pod", "nacelle": {"len": 0.20, "r": 0.04, "pylon": true}}),
			_edf(Vector3(-0.34, -0.15, 0.66), 50.0, 11.0, 42.0, 30.0, 0.13, {"intake": "pod", "nacelle": {"len": 0.21, "r": 0.04, "pylon": true}}),
			_edf(Vector3(0.34, -0.15, 0.66), 50.0, 11.0, 42.0, 30.0, 0.13, {"intake": "pod", "nacelle": {"len": 0.21, "r": 0.04, "pylon": true}, "spin": -1}),
			_edf(Vector3(0.60, -0.14, 0.78), 50.0, 11.0, 42.0, 30.0, 0.13, {"intake": "pod", "nacelle": {"len": 0.20, "r": 0.04, "pylon": true}, "spin": -1})],
		"gear": {"type": "tricycle", "retract": true, "wheels": [
			_wheel(0, -0.18, 0.24, 0.028, {"len": 0.08, "steer": true, "style": "oleo", "brake": false, "twin": true}),
			_wheel(-0.16, -0.19, 0.98, 0.034, {"len": 0.08, "style": "bogie"}),
			_wheel(0.16, -0.19, 0.98, 0.034, {"len": 0.08, "style": "bogie"}),
			_wheel(-0.07, -0.19, 1.02, 0.034, {"len": 0.08, "style": "bogie"}),
			_wheel(0.07, -0.19, 1.02, 0.034, {"len": 0.08, "style": "bogie"})]},
		"cg": 0.24, "rates": {"ail": 18.0, "elev": 16.0, "rud": 22.0, "flap": 35.0},
		"livery": {"scheme": "airliner", "base": Color(0.97, 0.97, 0.98), "a1": Color(0.07, 0.20, 0.62), "a2": Color(0.25, 0.60, 0.90)},
		"labels": [{"text": "SKYLINER", "z": 0.45, "y": 0.07, "size": 0.045, "color": Color(0.07, 0.2, 0.62)},
			{"text": "74", "z": 1.62, "y": 0.34, "size": 0.08, "color": Color(0.97, 0.97, 0.98), "vtail": true}],
		"batteries": [_batt("2x 4S 3300 mAh (parallel)", 4, 6.6, 0.74), _batt("2x 4S 4000 mAh (parallel)", 4, 8.0, 0.86)],
		"body_cd": 0.08, "gear_drag": 0.02, "strength": 1.0, "details": {"windows": true, "hump": true},
	}))

	# 16 ── SST: Mach Arrow (Concorde-style delta, elevons, 4 EDF)
	L.append(_base({
		"id": "macharrow", "name": "Mach Arrow SST", "category": "Airliner",
		"blurb": "Slender delta supersonic-transport replica. Elevons, high-alpha landings, needs power on final.",
		"material": "composite", "mass": 3.6, "length": 2.05,
		"fuselage": [[0.0, 0.003, 0.003, -0.02, 2.0], [0.15, 0.035, 0.035, -0.008, 2.0], [0.35, 0.06, 0.065, 0.0, 2.0],
			[0.60, 0.07, 0.075, 0.0, 2.0], [1.50, 0.07, 0.075, 0.0, 2.0], [1.85, 0.05, 0.06, 0.01, 2.0],
			[2.05, 0.012, 0.03, 0.02, 2.0]],
		"canopy": {"z0": 0.26, "z1": 0.34, "hw": 0.045, "hh": 0.02, "y": 0.052, "style": "cockpit", "tint": Color(0.05, 0.06, 0.08)},
		"wings": [_wing(0.78, -0.05, 0.92, 1.05, 0.06, {"dihedral": 0.0, "incidence": 1.0, "washout": 0.0, "thick": 0.035,
			"camber": 0.0, "ail": [0.12, 0.92, 0.12], "flap": [], "sweep": 58.0, "tip_style": "square", "elevon": true, "stall_deg": 32.0, "x0": 0.06})],
		"htail": {},
		"vtails": [_vtail(1.45, 0.07, 0.34, 0.52, 0.14, {"sweep": 55.0, "rudder_cf": 0.3})],
		"engines": [
			_edf(Vector3(-0.22, -0.10, 1.55), 64.0, 13.0, 50.0, 45.0, 0.2, {"intake": "box", "nacelle": {"len": 0.40, "r": 0.04, "box": true}}),
			_edf(Vector3(-0.13, -0.10, 1.55), 64.0, 13.0, 50.0, 45.0, 0.2, {"intake": "box", "nacelle": {"len": 0.40, "r": 0.04, "box": true}}),
			_edf(Vector3(0.13, -0.10, 1.55), 64.0, 13.0, 50.0, 45.0, 0.2, {"intake": "box", "nacelle": {"len": 0.40, "r": 0.04, "box": true}, "spin": -1}),
			_edf(Vector3(0.22, -0.10, 1.55), 64.0, 13.0, 50.0, 45.0, 0.2, {"intake": "box", "nacelle": {"len": 0.40, "r": 0.04, "box": true}, "spin": -1})],
		"gear": {"type": "tricycle", "retract": true, "wheels": [
			_wheel(0, -0.26, 0.45, 0.026, {"len": 0.20, "steer": true, "style": "oleo", "brake": false, "twin": true}),
			_wheel(-0.16, -0.25, 1.30, 0.032, {"len": 0.19, "style": "bogie"}),
			_wheel(0.16, -0.25, 1.30, 0.032, {"len": 0.19, "style": "bogie"})]},
		"cg": 0.16, "rates": {"ail": 14.0, "elev": 16.0, "rud": 20.0, "flap": 0.0},
		"livery": {"scheme": "sst", "base": Color(0.98, 0.98, 0.99), "a1": Color(0.08, 0.14, 0.42), "a2": Color(0.80, 0.08, 0.12)},
		"labels": [{"text": "MACH ARROW", "z": 0.70, "y": 0.03, "size": 0.04, "color": Color(0.08, 0.14, 0.42)}],
		"batteries": [_batt("2x 4S 4000 mAh (parallel)", 4, 8.0, 0.86), _batt("2x 4S 5000 mAh (parallel)", 4, 10.0, 1.02)],
		"body_cd": 0.07, "gear_drag": 0.02, "strength": 1.0, "details": {"windows": true},
	}))
	return L