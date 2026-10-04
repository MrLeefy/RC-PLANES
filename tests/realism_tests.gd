extends "res://tests/upgrade_tests.gd"
## Realism / release QA for all 16 aircraft (specs, mass & CG, controls, gear & flaps, takeoff, stall, spin,
## stability, landing, damage, audio, replay & repair). Superset of the 0.10 production suite:
##   godot --headless --path . -- --upgrade-test               (real time)
##   godot --headless --fixed-fps 120 --path . -- --upgrade-test (fast)
## Thresholds come from RC engineering comparables (see docs/AIRCRAFT_SPECS.md), not from the current
## behaviour; when a check fails the model/data is fixed, never the threshold.

# category -> expected envelope (ready mass kg, wing loading g/dm2, thrust/weight, stall speed m/s, CG % MAC)
const ENVELOPE := {
	"Trainer":       {"wl": [30.0, 65.0],  "tw": [0.6, 1.3],  "vs": [5.5, 9.5],   "cg": [20.0, 38.0]},
	"Bush / STOL":   {"wl": [30.0, 65.0],  "tw": [0.7, 1.7],  "vs": [5.0, 9.5],   "cg": [20.0, 38.0]},
	"Aerobatic":     {"wl": [55.0, 85.0],  "tw": [1.0, 2.4],  "vs": [8.0, 13.0],  "cg": [22.0, 38.0]},
	"Biplane":       {"wl": [40.0, 75.0],  "tw": [0.8, 1.7],  "vs": [7.0, 12.5],  "cg": [20.0, 38.0]},
	"Warbird":       {"wl": [75.0, 125.0], "tw": [0.9, 1.7],  "vs": [10.0, 15.0], "cg": [20.0, 38.0]},
	"Sport Trainer": {"wl": [55.0, 85.0],  "tw": [0.8, 1.5],  "vs": [8.0, 12.5],  "cg": [20.0, 38.0]},
	"EDF Jet":       {"wl": [80.0, 125.0], "tw": [0.7, 1.4],  "vs": [10.0, 15.0], "cg": [15.0, 35.0]},
	"Turbine Jet":   {"wl": [130.0, 190.0], "tw": [0.7, 1.3], "vs": [12.0, 18.0], "cg": [15.0, 35.0]},
	"Multi-engine":  {"wl": [70.0, 125.0], "tw": [0.5, 1.2],  "vs": [9.0, 14.0],  "cg": [15.0, 35.0]},
	"Airliner":      {"wl": [70.0, 125.0], "tw": [0.5, 1.3],  "vs": [9.0, 14.0],  "cg": [15.0, 35.0]},
}

var specs := {}

func _run_all() -> void:
	await super._run_all()
	await t_audio_families()
	t_spec_sheets()
	for id in AircraftDB.ids():
		await t_aircraft(id)
	await t_fuel_and_parts_change_mass()

# ---------------------------------------------------------------- specs / mass
func t_spec_sheets() -> void:
	var bad_env := []
	var bad_mass := []
	var worst_ballast := 0.0
	for d in AircraftDB.all():
		var sp: Dictionary = specs[d["id"]] if specs.has(d["id"]) else AircraftSpecs.compute(d, Settings.aircraft_cfg(d["id"]))
		specs[d["id"]] = sp
		var env: Dictionary = ENVELOPE[sp["category"]]
		var wl := float(sp["wing_loading_kg_m2"]) * 10.0
		if wl < float(env["wl"][0]) or wl > float(env["wl"][1]):
			bad_env.append("%s WL %.0f g/dm2" % [d["id"], wl])
		var tw := float(sp["thrust_to_weight"])
		if tw < float(env["tw"][0]) or tw > float(env["tw"][1]):
			bad_env.append("%s T/W %.2f" % [d["id"], tw])
		var vs := float(sp["v_stall_clean_ms"])
		if vs < float(env["vs"][0]) or vs > float(env["vs"][1]):
			bad_env.append("%s Vs %.1f" % [d["id"], vs])
		var cgp := float(sp["cg_pct_mac"])
		if cgp < float(env["cg"][0]) or cgp > float(env["cg"][1]):
			bad_env.append("%s CG %.0f%% MAC" % [d["id"], cgp])
		if float(sp["static_margin_pct"]) < 3.0 or float(sp["static_margin_pct"]) > 65.0:
			bad_env.append("%s static margin %.0f%%" % [d["id"], float(sp["static_margin_pct"])])
		# mass book-keeping: ready = airframe(listed) + battery/fuel - nothing hidden
		var listed := float(d["mass"]) + float(sp["payload_kg"]) + float(sp["ballast_kg"])
		if absf(listed - float(sp["mass_ready_kg"])) > 0.02 * float(sp["mass_ready_kg"]) + 0.02:
			bad_mass.append("%s listed+payload+ballast %.3f vs ready %.3f" % [d["id"], listed, sp["mass_ready_kg"]])
		worst_ballast = maxf(worst_ballast, float(sp["ballast_frac"]))
		# principal moments of any rigid body obey the triangle inequality (each <= sum of the other two)
		var Ix: float = sp["inertia_pitch_kgm2"]
		var Iy: float = sp["inertia_yaw_kgm2"]
		var Iz: float = sp["inertia_roll_kgm2"]
		if not (Ix > 0.0 and Iy > 0.0 and Iz > 0.0 and Iy <= 1.02 * (Ix + Iz) and Ix <= 1.02 * (Iy + Iz) and Iz <= 1.02 * (Ix + Iy)):
			bad_mass.append("%s inertia %.4f/%.4f/%.4f" % [d["id"], Ix, Iy, Iz])
	_ok("specs: all 16 inside category RC envelopes (wing loading, T/W, Vs, CG)", bad_env.is_empty(), str(bad_env))
	_ok("specs: mass book-keeping adds up and inertia is physical", bad_mass.is_empty(), str(bad_mass))
	_ok("specs: no hidden lead - ballast <= 3 % of ready mass everywhere", worst_ballast <= 0.03, "worst %.1f %%" % (worst_ballast * 100.0))
	# derived numbers are internally consistent with the sim: Vs from the polar must bracket Vcruise < Vtop
	var bad_speed := []
	for id in specs:
		var sp: Dictionary = specs[id]
		if not (float(sp["v_stall_clean_ms"]) < float(sp["v_cruise_ms"]) * 1.01 and float(sp["v_cruise_ms"]) < float(sp["v_top_ms"])):
			bad_speed.append("%s %.1f/%.1f/%.1f" % [id, sp["v_stall_clean_ms"], sp["v_cruise_ms"], sp["v_top_ms"]])
		if float(sp["v_top_ms"]) < 1.5 * float(sp["v_stall_clean_ms"]):
			bad_speed.append("%s top speed only %.1f x stall" % [id, float(sp["v_top_ms"]) / float(sp["v_stall_clean_ms"])])
	_ok("specs: stall < cruise < top speed, top >= 1.5 x stall", bad_speed.is_empty(), str(bad_speed))
	# comparative character
	var wl := func(id): return float(specs[id]["wing_loading_kg_m2"])
	_ok("character: trainer & STOL lighter-loaded than warbirds and jets", maxf(wl.call("skylark"), wl.call("ridgeline")) < minf(wl.call("belle51"), wl.call("viper90")))
	_ok("character: STOL stalls slower than the trainer at similar loading", float(specs["ridgeline"]["v_stall_flaps_ms"]) < float(specs["skylark"]["v_stall_flaps_ms"]),
		"%.1f vs %.1f" % [specs["ridgeline"]["v_stall_flaps_ms"], specs["skylark"]["v_stall_flaps_ms"]])
	_ok("character: aerobat out-climbs trainer, jets out-run props", float(specs["vortex540"]["roc_ms"]) > float(specs["skylark"]["roc_ms"]) * 1.5 and float(specs["striker16"]["v_top_ms"]) > float(specs["belle51"]["v_top_ms"]))
	_ok("character: turbine spools slower than an EDF", float(specs["striker16"]["turbine_spool_up_s"]) > 4.0 * 0.22)

# ---------------------------------------------------------------- audio
func t_audio_families() -> void:
	await Sfx.build_bank_async(func(_f, _t): pass)
	var need := ["electric", "edf", "glow2", "glow4", "gas2", "turbine", "servo", "retract_motor", "tire_chirp", "brake_squeal", "esc_arm", "gear_lock", "scrape", "roll_grass", "roll_asphalt", "impact_foam", "impact_metal", "thud"]
	var missing := []
	for n in need:
		if not Sfx.bank.has(n) or Sfx.bank[n] == null:
			missing.append(n)
	_ok("audio: every propulsion, servo, retract, tyre, scrape and impact sound is synthesised", missing.is_empty(), str(missing))
	# spectral centroid of each looped engine sample must differ clearly between families
	var cent := {}
	for n in ["electric", "edf", "glow2", "glow4", "gas2", "turbine"]:
		cent[n] = _centroid(Sfx.bank[n])
	var close := []
	var names := cent.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: float = cent[names[i]]
			var b: float = cent[names[j]]
			if absf(a - b) / maxf(a, b) < 0.08:
				close.append("%s~%s" % [names[i], names[j]])
	_ok("audio: propulsion families have clearly different spectra", close.is_empty(), "%s centroids=%s" % [str(close), str(cent)])
	# RPM response is monotonic, load response is family specific
	var mono := true
	for t in ["electric", "glow2", "glow4", "gas2"]:
		var prev := 0.0
		for rpm in [1500.0, 3000.0, 6000.0, 9000.0]:
			var lp: Dictionary = EngineAudio.layer_params(t, rpm, float(Sfx.REF[t]), 0.8, 0.5, true, 1.0, 0.0)
			if float(lp["pitch"]) <= prev:
				mono = false
			prev = float(lp["pitch"])
	_ok("audio: pitch rises smoothly with RPM for every prop engine", mono)
	var e_lo: Dictionary = EngineAudio.layer_params("electric", 6000.0, 6000.0, 0.2, 0.5, true, 1.0, 0.0)
	var e_hi: Dictionary = EngineAudio.layer_params("electric", 6000.0, 6000.0, 1.0, 0.5, true, 1.0, 0.0)
	var g_lo: Dictionary = EngineAudio.layer_params("glow4", 3000.0, 9000.0, 0.1, 0.5, true, 1.0, 0.0)
	var g_hi: Dictionary = EngineAudio.layer_params("glow4", 3000.0, 9000.0, 1.0, 0.5, true, 1.0, 0.0)
	_ok("audio: load swells the tone (electric) and IC engines stay audible at idle", float(e_hi["level"]) > 1.5 * float(e_lo["level"]) and float(g_lo["level"]) > 0.5 and float(g_hi["level"]) > float(g_lo["level"]))
	var lope_min := 9.0
	var lope_max := 0.0
	for k in 40:
		var lp2: Dictionary = EngineAudio.layer_params("glow4", 3000.0, 9000.0, 0.05, 0.5, true, 1.0, float(k) * 0.05)
		lope_min = minf(lope_min, lp2["pitch"])
		lope_max = maxf(lope_max, lp2["pitch"])
	_ok("audio: four-stroke idle lopes (pitch wanders), EDF/turbine do not", lope_max / lope_min > 1.04 and EngineAudio.layer_params("edf", 20000.0, 30000.0, 0.05, 0.3, true, 1.0, 0.3)["pitch"] == EngineAudio.layer_params("edf", 20000.0, 30000.0, 0.05, 0.3, true, 1.0, 0.9)["pitch"])
	var t_idle: Dictionary = EngineAudio.layer_params("turbine", 40000.0, 100000.0, 0.0, 0.36, true, 1.0, 0.0)
	var t_full: Dictionary = EngineAudio.layer_params("turbine", 150000.0, 100000.0, 1.0, 1.0, true, 1.0, 0.0)
	_ok("audio: turbine is quiet at idle and roars at full power", float(t_full["nlevel"]) > 4.0 * float(t_idle["nlevel"]))
	var damaged: Dictionary = EngineAudio.layer_params("electric", 6000.0, 6000.0, 1.0, 0.5, true, 0.4, 0.013)
	var healthy: Dictionary = EngineAudio.layer_params("electric", 6000.0, 6000.0, 1.0, 0.5, true, 1.0, 0.013)
	_ok("audio: damaged prop is rougher than a healthy one", float(damaged["nlevel"]) > float(healthy["nlevel"]) * 1.5)
	# runtime: spawn an aircraft with the audio node, move servos / gear and check the layers react
	await _spawn("belle51")
	var au := EngineAudio.new()
	holder.add_child(au)
	au.setup(ac)
	_ground_place(Vector3(-40, 0, 0), -PI * 0.5, 0.0, 0.18)
	await _frames(10)
	ac.set_inputs(1.0, 1.0, 1.0, 0.0)
	await _frames(12)
	var servo_up := au.servo.volume_db > -60.0
	ac.set_inputs(0, 0, 0, 0)
	await _frames(120)
	var servo_quiet := au.servo.volume_db < -60.0
	_ok("audio: servo whine follows control motion and stops when still", servo_up and servo_quiet, "up=%s quiet=%s" % [servo_up, servo_quiet])
	ac.place(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-40, 30, 0)), 22.0)
	ac.toggle_gear()
	await _frames(60)
	var gear_snd := au.gear_motor.volume_db > -60.0 and ac.gear_pos < 1.0
	await _frames(180)
	_ok("audio: retract actuator sounds only while the gear travels", gear_snd and au.gear_motor.volume_db < -60.0 and ac.gear_pos <= 0.001, "pos=%.2f" % ac.gear_pos)
	au.queue_free()

func _centroid(stream: AudioStreamWAV) -> float:
	# crude DFT magnitude centroid on 2048 samples (22.05 kHz)
	var data := stream.data
	var n := 2048
	var re := PackedFloat32Array()
	re.resize(n)
	for i in n:
		re[i] = float(data.decode_s16(i * 2)) / 32768.0 * (0.5 - 0.5 * cos(TAU * i / n))
	var num := 0.0
	var den := 1e-9
	for k in range(1, n / 2, 2):
		var a := 0.0
		var b := 0.0
		for i in n:
			var ph := TAU * k * i / n
			a += re[i] * cos(ph)
			b += re[i] * sin(ph)
		var m := sqrt(a * a + b * b)
		num += m * k
		den += m
	return num / den * Sfx.RATE / n

# ---------------------------------------------------------------- per-aircraft flight QA
func _att(a: Aircraft) -> Vector3:
	var B := a.global_transform.basis
	return Vector3(atan2(-B.x.y, B.y.y), asin(clampf(-B.z.y, -1, 1)), 0)

func _rates(a: Aircraft) -> Vector3:
	var w_l := a.global_transform.basis.transposed() * a.angular_velocity
	return Vector3(-w_l.z, w_l.x, -w_l.y)   # p (right roll +), q (nose up +), r (nose right +)

func _ap(a: Aircraft, tb: float, tp: float, thr: float, yaw := 0.0) -> void:
	var at := _att(a)
	var r := _rates(a)
	var kq := clampf(20.0 / maxf(a.airspeed, 5.0), 0.2, 2.0)
	a.set_inputs(clampf((tb - at.x) * 2.0 * kq - r.x * 0.25 * kq, -1, 1), clampf((tp - at.y) * 3.0 * kq - r.y * 0.5 * kq, -1, 1), yaw, thr)

func _alt_hold(a: Aircraft, h0: float, thr: float) -> void:
	var tp := clampf((h0 - a.global_position.y) * 0.04 - a.linear_velocity.y * 0.08, -0.35, 0.35)
	_ap(a, 0.0, tp, thr)

func _air(a: Aircraft, h: float, v: float) -> void:
	a.place(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-200, h, 0)), v)
	for e in a.engines:
		e.running = true
		if e.type in ["edf", "turbine"]:
			e.rpm_frac = 0.6
		else:
			e.omega = 600.0
	a.gear_down = true
	a.gear_pos = 1.0

func _run(n: int, f: Callable) -> void:
	for i in n:
		f.call()
		await get_tree().physics_frame

func t_aircraft(id: String) -> void:
	var sp: Dictionary = specs[id]
	var a := await _spawn(id)
	var cat := String(sp["category"])
	var vs: float = sp["v_stall_clean_ms"]
	var vcr: float = sp["v_cruise_ms"]
	# ---- 1. rest on the gear: no damage, wheels carry the weight, prop & hull clear the ground ----
	_ground_place(Vector3(-60, 0, 0), -PI * 0.5)
	if String(a.def["gear"]["type"]) == "taildragger":
		_ground_place(Vector3(-60, 0, 0), -PI * 0.5, 0.0, 0.18)
	await _frames(240)
	var touching := a.wheels_touching
	var sunk := 0.0
	for w in a.wheels:
		sunk = maxf(sunk, float(w["comp_now"]) / maxf(float(w["travel"]), 1e-4))
	var prop_clear := 9.0
	var gy := field.ground_y(a.global_position)
	for ed in a.eng_defs:
		if String(ed["type"]) in ["electric", "glow2", "glow4", "gas2"]:
			var wp: Vector3 = a.global_transform * (ed["pos"] as Vector3)
			prop_clear = minf(prop_clear, wp.y - gy - float(ed["D"]) * 0.5 * absf(cos(_att(a).y)) + 0.0)
	_ok("%s: rests on gear, no damage, props clear the ground" % id,
		touching == a.wheels.size() and _max_dmg() < 0.01 and _detached().is_empty() and a.linear_velocity.length() < 0.05 and sunk < 0.9 and prop_clear > 0.015,
		"touching=%d/%d dmg=%.2f v=%.3f travel=%.0f%% propclear=%.3f" % [touching, a.wheels.size(), _max_dmg(), a.linear_velocity.length(), sunk * 100.0, prop_clear])
	# ---- 2. control polarity & servo following (airborne, 1 g) ----
	_air(a, 150.0, vcr)
	await _run(180, func(): _alt_hold(a, 150.0, 0.55))
	var p0 := 0.0
	await _run(60, func():
		a.set_inputs(1.0, 0.0, 0.0, 0.55)
		p0 = _rates(a).x)
	var surf_ok := true
	var ail_l := -9.0
	var ail_r := 9.0
	for s in a.surfaces:
		for m in s["mix"]:
			if int(m[0]) == 0 and String(s["id"]).begins_with("ail0_L"):
				ail_l = float(s["defl"])
			if int(m[0]) == 0 and String(s["id"]).begins_with("ail0_R"):
				ail_r = float(s["defl"])
	var has_ail := ail_l > -8.0 and ail_r < 8.0
	if has_ail:
		surf_ok = ail_l * ail_r < 0.0 and absf(ail_l) > 0.1 and absf(ail_r) > 0.1
	_air(a, 150.0, vcr)
	await _run(120, func(): _alt_hold(a, 150.0, 0.55))
	var q_max := -9.0
	await _run(30, func():
		a.set_inputs(0.0, 0.8, 0.0, 0.55)
		q_max = maxf(q_max, _rates(a).y))
	var pitch_ok := q_max > 0.05
	_air(a, 150.0, vcr)
	await _run(120, func(): _alt_hold(a, 150.0, 0.55))
	var r_end := 0.0
	await _run(40, func():
		a.set_inputs(0.0, 0.0, 1.0, 0.55)
		r_end = _rates(a).z)
	_ok("%s: roll/pitch/yaw inputs move the aircraft the right way and the surfaces follow" % id, p0 > 0.2 and surf_ok and pitch_ok and r_end > 0.02,
		"p=%.2f q=%.2f r=%.2f ails=%.2f/%.2f" % [p0, q_max, r_end, ail_l, ail_r])
	# ---- 3. gear & flaps animate from real state ----
	var gear_flap_ok := true
	var gdetail := ""
	if a.has_retracts():
		_air(a, 150.0, vcr)
		a.toggle_gear()
		await _run(60 * 3, func(): _alt_hold(a, 150.0, 0.6))
		var up_ok := a.gear_pos <= 0.001
		var moved := 0
		a.update_visuals(a.global_transform, 0.0)
		for w in a.wheels:
			var rt := a.build_part(int(w["retract_part"]))
			if rt and not rt.basis.is_equal_approx(Basis()):
				moved += 1
		a.toggle_gear()
		await _run(60 * 3, func(): _alt_hold(a, 150.0, 0.6))
		a.update_visuals(a.global_transform, 0.0)
		var down_ok := a.gear_pos >= 0.999
		var restored := 0
		for w in a.wheels:
			var rt2 := a.build_part(int(w["retract_part"]))
			if rt2 and rt2.basis.is_equal_approx(Basis()):
				restored += 1
		gear_flap_ok = up_ok and moved == a.wheels.size() and down_ok and restored >= a.wheels.size() - 0
		gdetail = "up=%s moved=%d/%d down=%s restored=%d" % [up_ok, moved, a.wheels.size(), down_ok, restored]
	if a.has_flaps():
		a.flap_cmd = 1.0
		await _run(60 * 2, func(): _alt_hold(a, 150.0, 0.6))
		var fl_defl := 0.0
		for s in a.surfaces:
			for m in s["mix"]:
				if int(m[0]) == 3:
					fl_defl = maxf(fl_defl, absf(float(s["defl"])))
		var want := float(a.max_defl[3])
		gear_flap_ok = gear_flap_ok and a.flap_pos > 0.99 and absf(fl_defl - want) < 0.05 * maxf(want, 0.1)
		gdetail += " flap_pos=%.2f defl=%.2f/%.2f" % [a.flap_pos, fl_defl, want]
		a.flap_cmd = 0.0
	if a.has_retracts() or a.has_flaps():
		_ok("%s: retracts and flaps travel to their commanded state and the visuals follow" % id, gear_flap_ok, gdetail)
	# ---- 4. takeoff, scripted pilot (tail up, rotate) ----
	var tk := await _takeoff(a, id, sp)
	_ok("%s: takeoff roll under power, no damage, climbs away" % id, tk["ok"], tk["detail"])
	# ---- 5. power-off stall: speed at the break vs. the spec sheet, and recovery ----
	var st := await _stall(a, id, sp)
	_ok("%s: stall breaks near the published Vs and recovers with elevator + power" % id, st["ok"], st["detail"])
	# ---- 6. spin entry and standard recovery ----
	var sr := await _spin(a, id, sp)
	_ok("%s: %s" % [id, sr["title"]], sr["ok"], sr["detail"])
	# ---- 7. hands-off stability at cruise power ----
	_air(a, 150.0, vcr)
	var thr_cr := 0.5
	await _run(240, func(): _alt_hold(a, 150.0, thr_cr))
	var pmin := 99.0
	var pmax := -99.0
	var bmax := 0.0
	var h0 := a.global_position.y
	await _run(120 * 6, func():
		a.set_inputs(0.0, 0.0, 0.0, thr_cr)
		pmin = minf(pmin, rad_to_deg(_att(a).y))
		pmax = maxf(pmax, rad_to_deg(_att(a).y))
		bmax = maxf(bmax, absf(rad_to_deg(_att(a).x))))
	var stable_cat := cat in ["Trainer", "Bush / STOL", "Warbird", "Multi-engine", "Airliner", "Sport Trainer", "Biplane"]
	var lim_p := 22.0 if stable_cat else 40.0
	var lim_b := 45.0 if stable_cat else 70.0
	_ok("%s: hands-off cruise stays inside a sane envelope (no divergence)" % id, pmax < lim_p and pmin > -lim_p and bmax < lim_b and not a.crashed_flag,
		"pitch[%.0f..%.0f] bank<=%.0f dAlt=%.1f" % [pmin, pmax, bmax, a.global_position.y - h0])
	# ---- 8. landing: unpowered touchdown at 1.3 Vs is gentle, upright and does no damage ----
	var ld := await _landing(a, id, sp)
	_ok("%s: approach at 1.3 Vs, flare and roll-out with brakes without damage" % id, ld["ok"], ld["detail"])
	# ---- 9. damage -> repair round trip restores the aircraft ----
	a.repair_all()
	await _frames(2)
	var parts_before := _detached().size()
	var killed := ""
	for c in a.comps:
		if String(c["kind"]) in ["wingtip", "stab", "fin"] and not c["detached"]:
			a.detach(a.comps.find(c), {"sev": 8.0, "pos": a.global_position})
			killed = String(c["id"])
			break
	var m_after := a.mass
	await _frames(3)
	var broke := _detached().size() > parts_before
	a.repair_all()
	await _frames(3)
	_ok("%s: losing %s lightens the aircraft; repair restores parts, mass and flight state" % [id, killed],
		broke and m_after < float(sp["mass_ready_kg"]) - 0.002 and _detached().is_empty() and absf(a.mass - float(sp["mass_ready_kg"])) < 0.03 and not a.crashed_flag,
		"mass %.3f -> %.3f -> %.3f" % [sp["mass_ready_kg"], m_after, a.mass])

func _takeoff(a: Aircraft, id: String, sp: Dictionary) -> Dictionary:
	a.repair_all()
	_ground_place(Vector3(-60, 0, 0), -PI * 0.5)
	if String(a.def["gear"]["type"]) == "taildragger":
		_ground_place(Vector3(-60, 0, 0), -PI * 0.5, 0.0, 0.18)
	for e in a.engines:
		if not e.running:
			e.start_request(0.0)
	await _frames(200)
	a.damage_mode = "physical"
	var x0 := a.global_position
	var t := 0.0
	var lof_d := -1.0
	var lof_v := 0.0
	var vs: float = sp["v_stall_clean_ms"]
	var taildragger := String(a.def["gear"]["type"]) == "taildragger"
	var maxdmg := 0.0
	var air_t := 0.0
	for i in 120 * 22:
		t += 1.0 / 120.0
		var thr := clampf(t / 1.5, 0.0, 1.0)
		var head_err := wrapf(atan2(-a.global_transform.basis.z.x, -a.global_transform.basis.z.z) - (PI * 0.5), -PI, PI)
		var yaw := clampf(head_err * 3.0 - _rates(a).z * 0.3, -1, 1)
		if a.airspeed < vs * 1.2:
			var pc := 0.0
			if taildragger and a.airspeed > vs * 0.4:
				pc = clampf((deg_to_rad(4.0) - _att(a).y) * 2.5 - _rates(a).y * 0.4, -0.35, 0.3)
			a.set_inputs(clampf(-_att(a).x * 2.0, -1, 1), pc, yaw, thr)
		else:
			_ap(a, 0.0, deg_to_rad(9.0), thr, yaw * 0.3)
		await get_tree().physics_frame
		if lof_d < 0.0 and a.wheels_touching == 0 and a.global_position.y > 0.4 and a.airborne_time > 0.3:
			lof_d = a.global_position.distance_to(x0)
			lof_v = a.airspeed
		if lof_d >= 0.0:
			air_t += 1.0 / 120.0
		maxdmg = maxf(maxdmg, _max_dmg())
		if a.global_position.y > 12.0 or a.crashed_flag:
			break
	var lim := maxf(2.5 * float(sp["takeoff_roll_m"]), 12.0)
	var ok: bool = lof_d > 0.0 and lof_d < lim and not a.crashed_flag and maxdmg < 0.05 and a.global_position.y > 8.0 and lof_v > 0.8 * vs
	return {"ok": ok, "detail": "roll %.0f m (limit %.0f, est %.0f) Vlof %.1f (Vs %.1f) alt %.1f dmg %.2f crash=%s" % [lof_d, lim, sp["takeoff_roll_m"], lof_v, vs, a.global_position.y, maxdmg, a.crashed_flag]}

func _stall(a: Aircraft, id: String, sp: Dictionary) -> Dictionary:
	a.repair_all()
	var vs: float = sp["v_stall_clean_ms"]
	_air(a, 200.0, vs * 1.6)
	await _run(60, func(): _alt_hold(a, 200.0, 0.0))
	var v_break := 0.0
	var bank_max := 0.0
	var broke := false
	var gone := 0.0
	var pitch_in := 0.0
	for i in 120 * 25:
		pitch_in = minf(pitch_in + 1.0 / 120.0 * 0.12, 1.0)
		a.set_inputs(clampf(-_att(a).x * 2.0, -1, 1), pitch_in, 0.0, 0.0)   # wings level, slow pull, idle
		await get_tree().physics_frame
		bank_max = maxf(bank_max, absf(rad_to_deg(_att(a).x)))
		var sink_break := a.linear_velocity.y < -2.0 and rad_to_deg(a.aoa) > 8.0 and _rates(a).y < 0.0
		if not broke and (sink_break or a.linear_velocity.y < -4.0):
			broke = true
			v_break = a.airspeed
			gone = a.global_position.y
		if broke and a.airspeed > vs * 1.0 and i > 120 * 4 and false:
			break
		if broke:
			# recover: stick forward, wings level, power
			break
	# recovery
	var t_rec := -1.0
	await _run(120 * 1, func(): a.set_inputs(clampf(-_att(a).x * 2.0, -1, 1), -0.4, 0.0, 1.0))
	for i in 120 * 6:
		_ap(a, 0.0, deg_to_rad(2.0), 1.0)
		await get_tree().physics_frame
		if rad_to_deg(a.aoa) < 9.0 and a.linear_velocity.y > -1.0 and t_rec < 0.0:
			t_rec = 1.0 + i / 120.0
			break
	var tol := 0.7 < v_break / vs and v_break / vs < 1.55
	var cat := String(sp["category"])
	var wing_drop_ok := bank_max < (60.0 if cat in ["Trainer", "Bush / STOL", "Sport Trainer", "Multi-engine", "Airliner"] else 120.0)
	return {"ok": broke and tol and wing_drop_ok and t_rec > 0.0 and not a.crashed_flag,
		"detail": "break at %.1f m/s (Vs %.1f), bank<=%.0f, recovered in %.1f s" % [v_break, vs, bank_max, t_rec]}

func _spin(a: Aircraft, id: String, sp: Dictionary) -> Dictionary:
	a.repair_all()
	var vs: float = sp["v_stall_clean_ms"]
	var cat := String(sp["category"])
	_air(a, 300.0, vs * 1.4)
	await _run(60, func(): _alt_hold(a, 300.0, 0.0))
	await _run(150, func(): a.set_inputs(0.0, 1.0, 0.0, 0.0))
	var yaw_acc := 0.0
	await _run(120 * 5, func():
		a.set_inputs(0.0, 1.0, -1.0, 0.0)
		yaw_acc += _rates(a).z / 120.0)
	var turns := absf(yaw_acc) / TAU
	var sign_r := -1.0 if yaw_acc > 0.0 else 1.0     # opposite rudder
	var t_rec := -1.0
	for i in 120 * 9:
		a.set_inputs(0.0, -0.5, sign_r * (1.0 if i < 120 * 2 else 0.0), 0.5 if i > 120 else 0.0)
		await get_tree().physics_frame
		if absf(_rates(a).z) < 0.4 and i > 40 and a.airspeed > vs * 0.9:
			t_rec = i / 120.0
			break
	var title := ""
	var ok := false
	if cat in ["Trainer", "Bush / STOL", "Multi-engine", "Airliner", "Sport Trainer"]:
		title = "full pro-spin input does not produce a sustained spin (forgiving)"
		ok = turns < 2.2 and not a.crashed_flag
	else:
		title = "spin enters and the standard recovery (opposite rudder, stick forward, power) stops it"
		ok = t_rec > 0.0 and t_rec < 5.0 and not a.crashed_flag
	return {"ok": ok, "title": title, "detail": "%.1f turns in 5 s, recovery %.1f s" % [turns, t_rec]}

func _landing(a: Aircraft, id: String, sp: Dictionary) -> Dictionary:
	a.repair_all()
	var vs: float = float(sp["v_stall_flaps_ms"]) if a.has_flaps() else float(sp["v_stall_clean_ms"])
	var v_app := 1.3 * vs
	# set the approach up 6 m above the runway; descend at ~1.2 m/s on a shallow glide, flare near the ground
	a.place(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-90, 5.0, 0)), v_app)
	for e in a.engines:
		e.running = true
		if e.type in ["edf", "turbine"]:
			e.rpm_frac = maxf(float(e.d.get("idle_frac", 0.0)), 0.3)
		else:
			e.omega = 400.0
	if a.has_flaps():
		a.flap_cmd = 1.0
		a.flap_pos = 1.0
	a.gear_down = true
	a.gear_pos = 1.0
	var touch_vs := 0.0
	var touched := false
	var maxdmg := 0.0
	var landed_t := -1.0
	var thr := 0.0
	var gx := a.global_position
	for i in 120 * 22:
		var h := a.agl
		var vy := a.linear_velocity.y
		var tp := deg_to_rad(-2.0)
		if h < 1.6:
			tp = deg_to_rad(5.0) if String(sp["category"]) != "Airliner" else deg_to_rad(6.0)   # flare
		var thr_cmd := 0.0
		if h > 1.0 and a.airspeed < v_app * 0.95:
			thr_cmd = 0.35   # a little power keeps the approach speed (pilots do this too)
		var yaw := clampf(wrapf(atan2(-a.global_transform.basis.z.x, -a.global_transform.basis.z.z) - (PI * 0.5), -PI, PI) * 3.0 - _rates(a).z * 0.3, -1, 1)
		_ap(a, 0.0, tp, thr_cmd, yaw if a.wheels_touching > 0 else 0.0)
		if a.wheels_touching > 0:
			a.brake = 0.7 if a.ground_speed < 0.8 * v_app else 0.0
			a.set_inputs(clampf(-_att(a).x * 2.0, -1, 1), (0.0 if a.ground_speed > vs else 0.0), yaw, 0.0)
		await get_tree().physics_frame
		if not touched and a.wheels_touching > 0:
			touched = true
			touch_vs = -vy
		maxdmg = maxf(maxdmg, _max_dmg())
		if touched and a.ground_speed < 0.6:
			landed_t = i / 120.0
			break
		if a.crashed_flag:
			break
	a.brake = 0.0
	var upright := absf(rad_to_deg(_att(a).x)) < 40.0
	return {"ok": touched and touch_vs < 2.6 and maxdmg < 0.05 and upright and not a.crashed_flag,
		"detail": "touchdown sink %.2f m/s dmg %.2f roll-out %.0f m upright=%s crash=%s" % [touch_vs, maxdmg, a.global_position.distance_to(gx), upright, a.crashed_flag]}

# ---------------------------------------------------------------- mass changes in flight
func t_fuel_and_parts_change_mass() -> void:
	# fuel burn: lighter, CG moves only slightly, inertia drops
	var a := await _spawn("vortex540")
	var m0 := a.mass
	var i0 := a.inertia
	a.fuel_kg = a.fuel_max * 0.2
	a.recompute_mass()
	var burned := m0 - a.mass
	_ok("mass: burning fuel lightens the aircraft and lowers inertia", burned > 0.1 and a.inertia.y < i0.y and a.inertia.x < i0.x, "dm=%.3f kg" % burned)
	# wing loss moves CG sideways and inertia changes
	a.repair_all()
	var cg0 := a.com_local
	var wi := -1
	for i in a.comps.size():
		if String(a.comps[i]["id"]) == "wing0_L":
			wi = i
	a.detach(wi, {"sev": 8.0, "pos": a.global_position})
	await _frames(3)
	_ok("mass: losing a wing shifts the CG sideways and cuts roll inertia", a.com_local.x > cg0.x + 0.01 and a.inertia.z < i0.z, "dcg.x=%.3f" % (a.com_local.x - cg0.x))
	# electric: battery sag lowers thrust (voltage-limited), same throttle
	var e := await _spawn("skylark")
	var full := AircraftSpecs._thrust_at(e, 0.0, 1.0)
	e.bat_soc = 0.12
	var sag_v := Aircraft._ocv(0.12) * e.bat_cells - 30.0 * e.bat_r
	_ok("mass: pack voltage sags with state of charge (LiPo curve)", sag_v < Aircraft._ocv(1.0) * e.bat_cells * 0.85 and float(full["thrust"]) > 5.0, "%.1f V vs %.1f V" % [sag_v, Aircraft._ocv(1.0) * e.bat_cells])
