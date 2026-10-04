class_name AircraftSpecs
extends RefCounted
## Derives a "spec sheet" for every aircraft from the same data the simulation flies with
## (geometry, component masses, propulsion models, aerodynamic panels) - nothing here is typed in
## by hand, so the sheet cannot disagree with the sim.
##
## All aircraft are FICTIONAL RC designs "in the style of" real types. The numbers are what a
## comparable real RC model of that size/category would plausibly carry (see docs/AIRCRAFT_SPECS.md
## for the assumptions); they are NOT official manufacturer data and no real product is implied.
##
## Estimated speeds use the simulation's own aerodynamic panels in steady level flight (weight
## carried, factory elevator trim), so they match what the flight model actually does.

const RHO := 1.225
const G := 9.81

## Build a throw-away display aircraft for the definition + workshop config and read it out.
static func compute(def: Dictionary, cfg := {}) -> Dictionary:
	var ac := Aircraft.new()
	ac.setup(def, cfg, 0, true)
	var sp := from_aircraft(ac)
	ac.free()
	return sp

static func from_aircraft(ac: Aircraft) -> Dictionary:
	var d := ac.def
	var b := ac.build
	var sp := {"id": d["id"], "name": d["name"], "category": d["category"], "material": d["material"]}
	# ---- geometry ----
	var area := 0.0
	var span := 0.0
	for w in d["wings"]:
		area += float(w["span"]) * 0.5 * (float(w["root"]) + float(w["tip"]))
		span = maxf(span, float(w["span"]))
	var mac: Dictionary = b["mac"]
	sp["span_m"] = span
	sp["length_m"] = float(d["length"])
	sp["wing_area_m2"] = area
	sp["mac_m"] = float(mac["c"])
	sp["aspect_ratio"] = span * span / maxf(area, 1e-4) if d["wings"].size() == 1 else span * span / maxf(area * 0.5 * 2.0, 1e-4)
	var htail: Dictionary = d["htail"]
	sp["htail_area_m2"] = 0.0 if htail.is_empty() else float(htail["span"]) * 0.5 * (float(htail["root"]) + float(htail["tip"]))
	var fin_area := 0.0
	for v in d["vtails"]:
		fin_area += float(v["height"]) * 0.5 * (float(v["root"]) + float(v["tip"]))
	sp["vtail_area_m2"] = fin_area
	# ---- mass / CG / inertia ----
	var ready := ac.mass
	var pay := float(b["payload_mass"])
	sp["mass_ready_kg"] = ready
	sp["mass_airframe_kg"] = float(d["mass"])
	sp["payload_kind"] = String(b["payload_kind"])
	sp["payload_kg"] = pay
	sp["ballast_kg"] = float(b["ballast"])
	sp["radio_gear_kg"] = float(b["radio_mass"])
	var cgf: Vector2 = b["cg_free"]
	sp["cg_slide_range_pct"] = [cgf.x * 100.0, cgf.y * 100.0] if String(b["payload_kind"]) == "battery" else []
	sp["ballast_frac"] = float(b["ballast"]) / maxf(ready, 1e-3)
	sp["mass_dry_kg"] = ready - pay
	sp["wing_loading_kg_m2"] = ready / maxf(area, 1e-4)
	sp["wing_loading_oz_ft2"] = ready * 35.274 / (area * 10.7639)
	var cg_z := ac.com_local.z
	sp["cg_from_nose_m"] = cg_z
	sp["cg_pct_mac"] = (cg_z - float(mac["zle"])) / maxf(float(mac["c"]), 1e-4) * 100.0
	sp["static_margin_pct"] = ac.static_margin() * 100.0
	var I := ac.inertia
	sp["inertia_roll_kgm2"] = I.z
	sp["inertia_pitch_kgm2"] = I.x
	sp["inertia_yaw_kgm2"] = I.y
	sp["gyradius_roll_m"] = sqrt(I.z / ready)
	sp["gyradius_pitch_m"] = sqrt(I.x / ready)
	sp["gyradius_yaw_m"] = sqrt(I.y / ready)
	# ---- propulsion ----
	_propulsion(ac, sp)
	# ---- aerodynamics: stall, cruise, top speed, climb ----
	var W := ready * G
	var clmax := ac.cl_max(0.0)
	sp["cl_max_clean"] = clmax
	sp["v_stall_clean_ms"] = sqrt(2.0 * W / (RHO * area * maxf(clmax, 0.1)))
	var clf := clmax
	if ac.has_flaps():
		clf = ac.cl_max(1.0)
	sp["cl_max_flaps"] = clf
	sp["v_stall_flaps_ms"] = sqrt(2.0 * W / (RHO * area * maxf(clf, 0.1)))
	var vs: float = sp["v_stall_flaps_ms"]
	sp["v_approach_ms"] = vs * 1.3
	sp["v_liftoff_ms"] = float(sp["v_stall_clean_ms"]) * 1.2
	# level flight: thrust available vs. drag
	var vmax := _solve_speed(ac, sp, 1.0)
	var vcr := _solve_speed(ac, sp, 0.5)
	sp["v_top_ms"] = vmax["v"]
	sp["v_cruise_ms"] = vcr["v"]
	sp["amps_cruise"] = vcr["current"]
	sp["thrust_top_N"] = vmax["thrust"]
	# endurance: 80 % of pack capacity (LiPo, no abuse) or the whole tank, at half throttle / full throttle
	if sp.has("battery_Ah"):
		sp["endurance_cruise_min"] = float(sp["battery_Ah"]) * 0.8 / maxf(float(vcr["current"]), 0.1) * 60.0
		sp["endurance_full_min"] = float(sp["battery_Ah"]) * 0.8 / maxf(float(sp["amps_peak"]), 0.1) * 60.0
	else:
		sp["endurance_cruise_min"] = float(sp["fuel_mass_kg"]) / maxf(float(vcr["burn"]), 1e-7) / 60.0
		sp["endurance_full_min"] = float(sp["fuel_mass_kg"]) / maxf(float(sp["fuel_burn_full_g_min"]) / 60000.0, 1e-7) / 60.0
	# climb at 1.35 Vs, full power
	var vy := maxf(float(sp["v_stall_clean_ms"]) * 1.35, 4.0)
	var lf := ac.level_flight(vy)
	var t_vy := _thrust_at(ac, vy, 1.0)
	var excess := float(t_vy["thrust"]) - float(lf["drag"])
	sp["roc_ms"] = excess * vy / W
	# ground roll estimate (mean thrust at 0.7 Vlof, rolling friction 0.04 on tarmac/short grass)
	var vlof: float = sp["v_liftoff_ms"]
	var t_roll := _thrust_at(ac, vlof * 0.7, 1.0)
	var a_roll := G * (float(t_roll["thrust"]) / W - 0.04)
	sp["takeoff_roll_m"] = vlof * vlof / (2.0 * a_roll) if a_roll > 0.05 else INF
	# ---- servos / surfaces ----
	var r: Dictionary = d["rates"]
	sp["throw_aileron_deg"] = float(r["ail"])
	sp["throw_elevator_deg"] = float(r["elev"])
	sp["throw_rudder_deg"] = float(r["rud"])
	sp["throw_flap_deg"] = float(r["flap"])
	sp["servo_speed_dps"] = float(d["servo_speed"])
	sp["servo_sec_per_60deg"] = 60.0 / maxf(float(d["servo_speed"]), 1.0)
	sp["gear_retract"] = bool(d["gear"]["retract"])
	sp["gear_type"] = String(d["gear"]["type"])
	sp["wheel_count"] = (d["gear"]["wheels"] as Array).size()
	return sp

# ------------------------------------------------------------------ propulsion
static func _make_engines(ac: Aircraft) -> Array:
	var out := []
	for ed in ac.eng_defs:
		var pr := Propulsion.new()
		pr.setup(ed)
		pr.running = true
		out.append(pr)
		if pr.type in ["glow2", "glow4", "gas2"]:
			pr.omega = float(pr.d["rpm_peak"]) * 0.2 * TAU / 60.0
		elif pr.type == "turbine":
			pr.rpm_frac = float(pr.d["idle_frac"])
	return out

## Steady-state thrust/current of all engines at airspeed v and throttle thr.
static func _thrust_at(ac: Aircraft, v: float, thr: float) -> Dictionary:
	var engs := _make_engines(ac)
	var cells := float(ac.bat_cells)
	var total_i := 0.0
	var thrust := 0.0
	var rpm := 0.0
	var power_in := 0.0
	var shaft := 0.0
	var burn := 0.0
	var torque := 0.0
	var etype := String(ac.def["engines"][0]["type"])
	var dt := 0.005
	var steps := 600 if etype in ["electric", "edf"] else (1400 if etype == "turbine" else 700)
	if etype == "turbine":
		dt = 0.01
		steps = 1000
	for k in steps:
		var bat := {"v": 0.0, "v_nom": 1.0, "lvc": 1.0}
		if etype in ["electric", "edf"]:
			var vb := Aircraft._ocv(1.0) * cells - total_i * ac.bat_r
			bat = {"v": vb, "v_nom": 3.8 * cells, "lvc": 1.0}
		total_i = 0.0
		thrust = 0.0
		power_in = 0.0
		shaft = 0.0
		burn = 0.0
		torque = 0.0
		for e: Propulsion in engs:
			e.step(dt, thr, v, bat, true)
			thrust += e.thrust
			total_i += e.current
			rpm = maxf(rpm, e.rpm())
			shaft += e.power if etype not in ["electric", "edf"] else 0.0
			burn += e.fuel_burn_rate()
			torque += e.torque
		power_in = total_i * (bat["v"] as float)
	return {"thrust": thrust, "current": total_i, "rpm": rpm, "power_in": power_in, "shaft": shaft, "burn": burn, "torque": torque}

static func _propulsion(ac: Aircraft, sp: Dictionary) -> void:
	var d := ac.def
	var e0: Dictionary = d["engines"][0]
	var etype := String(e0["type"])
	sp["engine_type"] = etype
	sp["engine_count"] = (d["engines"] as Array).size()
	var st := _thrust_at(ac, 0.0, 1.0)
	sp["static_thrust_N"] = st["thrust"]
	sp["static_thrust_kgf"] = float(st["thrust"]) / G
	sp["thrust_to_weight"] = float(st["thrust"]) / (ac.mass * G)
	sp["rpm_static"] = st["rpm"]
	var eng_mass := 0.0
	for e in d["engines"]:
		eng_mass += float(e["mass"])
	sp["engine_mass_kg"] = eng_mass
	if etype in ["electric", "edf"]:
		var bats: Array = d["batteries"]
		var bi := clampi(int(ac.cfg.get("battery", 0)), 0, bats.size() - 1)
		var bt: Dictionary = bats[bi]
		sp["battery_name"] = bt["name"]
		sp["battery_cells"] = int(bt["cells"])
		sp["battery_Ah"] = float(bt["cap"])
		sp["battery_Wh"] = float(bt["cap"]) * 3.7 * float(bt["cells"])
		sp["battery_mass_kg"] = float(bt["mass"])
		sp["battery_Wh_per_kg"] = float(sp["battery_Wh"]) / maxf(float(bt["mass"]), 1e-3)
		sp["input_power_W"] = st["power_in"]
		sp["power_to_weight_W_kg"] = float(st["power_in"]) / ac.mass
		sp["amps_peak"] = st["current"]
		sp["c_rate_peak"] = float(st["current"]) / float(bt["cap"])
		if etype == "electric":
			sp["motor_kv"] = float(e0["kv"])
			sp["motor_rm_ohm"] = float(e0["rm"])
			sp["motor_i0_a"] = float(e0["i0"])
			sp["motor_mass_g"] = float(e0["mass"]) * 1000.0
		else:
			sp["fan_diameter_mm"] = float(e0["fan_d"]) * 1000.0
			sp["fan_static_thrust_N_each"] = float(e0["thrust"])
			sp["fan_rpm_max"] = float(e0["rpm_max"])
	else:
		sp["fuel_type"] = String(d["fuel_type"])
		sp["tank_L"] = float(d["tank"])
		sp["fuel_mass_kg"] = ac.fuel_max
		sp["shaft_power_W"] = st["shaft"]
		sp["shaft_power_hp"] = float(st["shaft"]) / 745.7
		sp["power_to_weight_W_kg"] = float(st["shaft"]) / ac.mass
		sp["fuel_burn_full_g_min"] = float(st["burn"]) * 60000.0
		if etype in ["glow2", "glow4", "gas2"]:
			sp["engine_peak_torque_Nm"] = float(e0["qmax"])
			sp["engine_rpm_peak"] = float(e0["rpm_peak"])
			sp["engine_rpm_max"] = float(e0["rpm_max"])
			sp["engine_idle_frac"] = float(e0["idle"])
		else:
			sp["turbine_thrust_N"] = float(e0["thrust"])
			sp["turbine_idle_frac"] = float(e0["idle_frac"])
			sp["turbine_spool_up_s"] = float(e0["spool_up"])
	if etype in ["electric", "glow2", "glow4", "gas2"]:
		var eng: Dictionary = ac.eng_defs[0]
		sp["prop_diameter_in"] = float(eng["D"]) / 0.0254
		sp["prop_pitch_in"] = float(eng["pitch"]) / 0.0254
		sp["prop_blades"] = int(eng["blades"])
		var rpm_s: float = sp["rpm_static"]
		sp["prop_pitch_speed_ms"] = rpm_s * float(eng["pitch"]) / 60.0

## Level-flight speed where thrust(v, thr) == drag(v). Returns v, thrust, current.
static func _solve_speed(ac: Aircraft, sp: Dictionary, thr: float) -> Dictionary:
	var lo := maxf(float(sp["v_stall_clean_ms"]) * 1.02, 3.0)
	var hi := 110.0
	var t := {}
	for it in 14:
		var v := (lo + hi) * 0.5
		var lf := ac.level_flight(v)
		t = _thrust_at(ac, v, thr)
		if float(t["thrust"]) > float(lf["drag"]):
			lo = v
		else:
			hi = v
	var v2 := (lo + hi) * 0.5
	t = _thrust_at(ac, v2, thr)
	return {"v": v2, "thrust": t["thrust"], "current": t["current"], "burn": t["burn"]}

## One-line human readable summary.
static func summary(sp: Dictionary) -> String:
	return "%s  %.2fm span  %.2f kg  WL %.1f kg/m2  T/W %.2f  Vs %.1f  Vcr %.1f  Vtop %.1f m/s" % [
		sp["name"], sp["span_m"], sp["mass_ready_kg"], sp["wing_loading_kg_m2"], sp["thrust_to_weight"],
		sp["v_stall_clean_ms"], sp["v_cruise_ms"], sp["v_top_ms"]]


## Markdown table for docs/AIRCRAFT_SPECS.md (generated by tests/spec_dump.tscn --md).
static func markdown(rows: Array) -> String:
	var o := "| Aircraft | Cat. | Span m | Length m | Area dm2 | MAC mm | AR | Ready kg | WL g/dm2 | CG %MAC | SM % | Ballast g |\n"
	o += "|---|---|---|---|---|---|---|---|---|---|---|---|\n"
	for r in rows:
		o += "| %s | %s | %.2f | %.2f | %.0f | %.0f | %.1f | %.2f | %.0f | %.0f | %.0f | %.0f |\n" % [r["name"], r["category"], r["span_m"], r["length_m"],
			float(r["wing_area_m2"]) * 100.0, float(r["mac_m"]) * 1000.0, r["aspect_ratio"], r["mass_ready_kg"], float(r["wing_loading_kg_m2"]) * 10.0,
			r["cg_pct_mac"], r["static_margin_pct"], float(r["ballast_kg"]) * 1000.0]
	o += "\n| Aircraft | Power | Static thrust N | T/W | W/kg | Vs clean | Vs flaps | Vapp | Vcruise | Vtop | ROC m/s | Takeoff roll m | Endurance cruise min |\n"
	o += "|---|---|---|---|---|---|---|---|---|---|---|---|---|\n"
	for r in rows:
		var pw := "%.0f W in" % float(r.get("input_power_W", 0.0)) if r.has("input_power_W") else "%.2f hp shaft" % float(r.get("shaft_power_hp", 0.0))
		if r["engine_type"] == "turbine":
			pw = "turbine %.0f N" % float(r["turbine_thrust_N"])
		o += "| %s | %s x%d | %.1f | %.2f | %.0f | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f | %.0f | %.1f |\n" % [r["name"], pw, r["engine_count"], r["static_thrust_N"],
			r["thrust_to_weight"], r["power_to_weight_W_kg"], r["v_stall_clean_ms"], r["v_stall_flaps_ms"], r["v_approach_ms"], r["v_cruise_ms"], r["v_top_ms"], r["roc_ms"],
			minf(float(r["takeoff_roll_m"]), 999.0), r["endurance_cruise_min"]]
	return o
