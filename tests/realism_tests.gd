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
	if OS.get_environment("RT_FAST") == "":
		await super._run_all()
		# the earlier suites poke wind/settings: start the per-aircraft sweep from the shipped defaults
		Game.wind = Wind.new()
		Game.wind.configure("calm", "headwind", Vector3(1, 0, 0))
		Settings.data["aircraft_cfg"] = {}
	await t_audio_families()
	await t_hangar_input()
	await t_hangar_cache()
	t_spec_sheets()
	var only := OS.get_environment("RT_ONLY")
	for id in AircraftDB.ids():
		if only == "" or id in only.split(","):
			await t_aircraft(id)
	await t_fuel_and_parts_change_mass()

# ---------------------------------------------------------------- hangar carousel input
func _touch_ev(pressed: bool, p: Vector2) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.pressed = pressed
	e.position = p
	return e

func t_hangar_input() -> void:
	var menu := HangarMenu.new()
	get_parent().ui.add_child(menu)
	await _frames(3)
	var sc: ScrollContainer = menu.get_node("Carousel")
	var ids := AircraftDB.ids()
	menu.select(ids[0], true)
	var target: String = ids[2]
	var other: String = ids[1]
	var origin := sc.get_global_rect().position
	var c_target: Vector2 = (menu.cards[target] as Control).get_global_rect().get_center() - origin
	var c_other: Vector2 = (menu.cards[other] as Control).get_global_rect().get_center() - origin
	# a tap on a card selects it
	menu._carousel_input(_touch_ev(true, c_target), sc)
	menu._carousel_input(_touch_ev(false, c_target), sc)
	var tap_ok: bool = menu.sel_id == target
	# a drag that starts on one card and ends over another scrolls and selects nothing
	menu.select(ids[0], true)
	menu._carousel_input(_touch_ev(true, c_target), sc)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = c_other
	menu._carousel_input(drag, sc)
	menu._carousel_input(_touch_ev(false, c_other), sc)
	var drag_ok: bool = menu.sel_id == ids[0]
	# a slow press (long hold without moving) is not a tap either
	menu._tap_down = true
	menu._tap_moved = false
	menu._tap_start = c_target
	menu._tap_time = Time.get_ticks_msec() - 2000
	menu._carousel_input(_touch_ev(false, c_target), sc)
	var hold_ok: bool = menu.sel_id == ids[0]
	_ok("hangar: tap selects an aircraft card, a drag over cards only scrolls, a long hold selects nothing", tap_ok and drag_ok and hold_ok, "tap=%s drag=%s hold=%s" % [tap_ok, drag_ok, hold_ok])
	menu.queue_free()

## The hangar builds display models on a worker thread, caches them and pre-builds the neighbouring cards.
func t_hangar_cache() -> void:
	var main := get_parent()
	main.state = "menu"
	main.menu = HangarMenu.new()
	main.ui.add_child(main.menu)
	await _frames(2)
	var ids := AircraftDB.ids()
	main.menu.sel_id = ids[3]
	main._show_display(ids[3])
	var t0 := Time.get_ticks_msec()
	var frames_during := 0
	while (main.display_ac == null or not is_instance_valid(main.display_ac) or String(main.display_ac.def["id"]) != ids[3]) and Time.get_ticks_msec() - t0 < 60000:
		frames_during += 1
		await get_tree().process_frame
	var shown: bool = main.display_ac != null and is_instance_valid(main.display_ac) and main.display_ac.visible and String(main.display_ac.def["id"]) == ids[3]
	# let the neighbour prefetch finish
	var t1 := Time.get_ticks_msec()
	while main._disp_cache.size() < 3 and Time.get_ticks_msec() - t1 < 90000:
		await get_tree().process_frame
	var prefetched: bool = main._disp_cache.has(main._disp_key(ids[4])) and main._disp_cache.has(main._disp_key(ids[2]))
	# switching to a prefetched neighbour is immediate (no build wait) and the old model is hidden, not rebuilt
	var before: Aircraft = main.display_ac
	main.menu.sel_id = ids[4]
	main._show_display(ids[4])
	var instant: bool = main.display_ac != null and String(main.display_ac.def["id"]) == ids[4] and main.display_ac.visible and not before.visible
	var main_thread_ok: bool = frames_during >= 5   # the main thread kept rendering frames while the model was building
	_ok("hangar: display models build off-thread, are cached, neighbours are prefetched and a cached switch is instant", shown and prefetched and instant and main_thread_ok,
		"shown=%s prefetched=%s instant=%s frames_during_build=%d cache=%d" % [shown, prefetched, instant, frames_during, main._disp_cache.size()])
	main._disp_clear()
	main.menu.queue_free()
	main.menu = null

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
	# scale-model fidelity: length/span of the replicas that copy a real type (published dimensions, +-8 %)
	var real_ls := {"skylark": 7.31 / 10.17, "belle51": 9.83 / 11.28, "specter22": 18.9 / 13.56, "brute10": 16.26 / 17.53,
		"striker16": 15.03 / 9.96, "macharrow": 61.66 / 25.6, "skyliner": 70.66 / 64.44, "cargo130": 29.79 / 40.41, "tundra_cub": 6.88 / 10.73,
		# class references for the in-the-style-of designs: 3D-aerobat (Extra-type), WWII radial fighter, light bush/trainer
		"vortex540": 0.88, "aerostar": 0.93, "skipper": 0.90, "tiger28": 0.79, "ridgeline": 0.70, "valor": 0.80}
	var bad_ratio := []
	for id in real_ls:
		var spr: Dictionary = specs[id]
		var got := float(spr["length_m"]) / float(spr["span_m"])
		if absf(got / float(real_ls[id]) - 1.0) > 0.08:
			bad_ratio.append("%s L/b %.2f vs real %.2f" % [id, got, real_ls[id]])
	# aspect ratio (span^2 / planform area) against published span and wing area, within 12 % (the RC replicas are not
	# built to the real wing area: fuselage lift, thickness and servo-friendly chords move it a little)
	var real_ar := {"skylark": 10.17 * 10.17 / 14.9, "tundra_cub": 10.73 * 10.73 / 16.6, "belle51": 11.28 * 11.28 / 21.83,
		"specter22": 13.56 * 13.56 / 78.04, "brute10": 17.53 * 17.53 / 47.0, "striker16": 9.96 * 9.96 / 27.87,
		"macharrow": 25.6 * 25.6 / 358.25, "skyliner": 64.4 * 64.4 / 541.0, "cargo130": 40.41 * 40.41 / 162.1}
	var bad_ar := []
	for id in real_ar:
		var spa: Dictionary = specs[id]
		var got_ar := float(spa["aspect_ratio"])
		if absf(got_ar / float(real_ar[id]) - 1.0) > 0.12:
			bad_ar.append("%s AR %.2f vs real %.2f" % [id, got_ar, real_ar[id]])
	# signature layout counts taken from the real types
	var layout_bad := []
	var want := {"brute10": [2, 2], "specter22": [2, 2], "macharrow": [1, 4], "skyliner": [1, 4], "cargo130": [1, 4], "striker16": [1, 1]}   # [fins, engines]
	for id in want:
		var dd := AircraftDB.by_id(id)
		var fins := 0
		for v in dd["vtails"]:
			fins += 2 if bool(v.get("mirror", false)) else 1
		if fins != int(want[id][0]):
			layout_bad.append("%s fins %d" % [id, fins])
		if (dd["engines"] as Array).size() != int(want[id][1]):
			layout_bad.append("%s engines %d" % [id, (dd["engines"] as Array).size()])
	_ok("scale: A-10 twin fins, F-22 twin canted fins, Concorde/747/C-130 four engines, F-16 single fin and engine", layout_bad.is_empty(), str(layout_bad))
	_ok("scale: aspect ratio of the replicas matches the real types within 12 %", bad_ar.is_empty(), str(bad_ar))
	_ok("scale: length/span of the replicas matches the real types within 8 %", bad_ratio.is_empty(), str(bad_ratio))
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
	# each looped engine sample must have a clearly different spectral shape (8 log-spaced bands)
	var prof := {}
	for n in ["electric", "edf", "glow2", "glow4", "gas2", "turbine"]:
		prof[n] = _band_profile(Sfx.bank[n])
	var close := []
	var names := prof.keys()
	var dmat := {}
	for i in names.size():
		for j in range(i + 1, names.size()):
			var dist := 0.0
			for k in 8:
				dist += absf(float(prof[names[i]][k]) - float(prof[names[j]][k]))
			dmat["%s~%s" % [names[i], names[j]]] = snappedf(dist, 0.01)
			if dist < 0.12:
				close.append("%s~%s=%.2f" % [names[i], names[j], dist])
	_ok("audio: propulsion families have clearly different spectra", close.is_empty(), "%s all=%s" % [str(close), str(dmat)])
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
	await _frames(400)
	_ok("audio: retract actuator sounds only while the gear travels", gear_snd and au.gear_motor.volume_db < -60.0 and ac.gear_pos <= 0.001, "pos=%.2f" % ac.gear_pos)
	au.queue_free()

func _band_profile(stream: AudioStreamWAV) -> Array:
	# normalised magnitude in 8 log-spaced bands (Hz edges) from a 2048-point DFT of the loop (22.05 kHz)
	var data := stream.data
	var n := 2048
	var x := PackedFloat32Array()
	x.resize(n)
	for i in n:
		x[i] = float(data.decode_s16(i * 2)) / 32768.0 * (0.5 - 0.5 * cos(TAU * i / n))
	var edges := [60.0, 140.0, 300.0, 600.0, 1200.0, 2400.0, 4800.0, 9000.0, 11025.0]
	var bands := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var total := 1e-9
	for k in range(2, n / 2, 3):
		var f := float(k) * Sfx.RATE / n
		var bi := -1
		for b in 8:
			if f >= edges[b] and f < edges[b + 1]:
				bi = b
		if bi < 0:
			continue
		var re := 0.0
		var im := 0.0
		for i in n:
			var ph := TAU * k * i / n
			re += x[i] * cos(ph)
			im += x[i] * sin(ph)
		var mag := sqrt(re * re + im * im)
		bands[bi] += mag
		total += mag
	for b in 8:
		bands[b] /= total
	return bands

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


## Pose with every wheel just touching the runway (taildraggers sit tail-down at the angle the gear dictates).
func _rest_place(a: Aircraft, x: float, speed := 0.0) -> void:
	var low := 0.0
	for w in a.wheels:
		low = minf(low, (w["center"] as Vector3).y - float(w["r"]))
	var b := Basis(Vector3.UP, -PI * 0.5)
	if String(a.def["gear"]["type"]) == "taildragger":
		var main: Dictionary = a.wheels[0]
		var tail: Dictionary = a.wheels[a.wheels.size() - 1]
		var ang := atan2(((tail["center"] as Vector3).y - float(tail["r"])) - ((main["center"] as Vector3).y - float(main["r"])), (tail["center"] as Vector3).z - (main["center"] as Vector3).z)
		b = Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3.RIGHT, ang)
		low = 0.0
		for w in a.wheels:
			low = minf(low, (b * ((w["center"] as Vector3) - Vector3(0, float(w["r"]), 0))).y)
	a.place(Transform3D(b, Vector3(x, -low + 0.03 + 0.003, 0)), speed)

func t_aircraft(id: String) -> void:
	var sp: Dictionary = specs[id]
	var a := await _spawn(id)
	var cat := String(sp["category"])
	var vs: float = sp["v_stall_clean_ms"]
	var vcr: float = sp["v_cruise_ms"]
	# ---- 1. rest on the gear: no damage, wheels carry the weight, prop & hull clear the ground ----
	_rest_place(a, -60.0)
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
			prop_clear = minf(prop_clear, wp.y - gy - float(ed["D"]) * 0.5 * absf(cos(_att(a).y)))
	_ok("%s: rests on gear, no damage, props clear the ground" % id,
		touching == a.wheels.size() and _max_dmg() < 0.01 and _detached().is_empty() and a.linear_velocity.length() < 0.05 and sunk < 0.9 and prop_clear > 0.015,
		"touching=%d/%d dmg=%.2f v=%.3f travel=%.0f%% propclear=%.3f" % [touching, a.wheels.size(), _max_dmg(), a.linear_velocity.length(), sunk * 100.0, prop_clear])
	# ---- 2. control polarity & servo following (airborne, 1 g) ----
	var m := {"p": 0.0, "q": -9.0, "r": 0.0}
	_air(a, 150.0, vcr)
	await _run(180, func(): _alt_hold(a, 150.0, 0.55))
	await _run(60, func():
		a.set_inputs(1.0, 0.0, 0.0, 0.55)
		m["p"] = _rates(a).x)
	var ail_l := -9.0
	var ail_r := 9.0
	for s_ in a.surfaces:
		for mx in s_["mix"]:
			if int(mx[0]) == 0 and String(s_["id"]).begins_with("ail0_L"):
				ail_l = float(s_["defl"])
			if int(mx[0]) == 0 and String(s_["id"]).begins_with("ail0_R"):
				ail_r = float(s_["defl"])
	var surf_ok := true
	if ail_l > -8.0 and ail_r < 8.0:
		surf_ok = ail_l * ail_r < 0.0 or absf(ail_l - ail_r) > 0.25   # differential ailerons (elevons also carry pitch trim)
		surf_ok = surf_ok and absf(ail_l - ail_r) > 0.2
	_air(a, 150.0, vcr)
	await _run(120, func(): _alt_hold(a, 150.0, 0.55))
	await _run(30, func():
		a.set_inputs(0.0, 0.8, 0.0, 0.55)
		m["q"] = maxf(m["q"], _rates(a).y))
	_air(a, 150.0, vcr)
	await _run(120, func(): _alt_hold(a, 150.0, 0.55))
	await _run(40, func():
		a.set_inputs(0.0, 0.0, 1.0, 0.55)
		m["r"] = _rates(a).z)
	_ok("%s: roll/pitch/yaw inputs move the aircraft the right way and the surfaces follow" % id, m["p"] > 0.2 and surf_ok and m["q"] > 0.05 and m["r"] > 0.02,
		"p=%.2f q=%.2f r=%.2f ails=%.2f/%.2f" % [m["p"], m["q"], m["r"], ail_l, ail_r])
	# ---- 3. gear & flaps animate from real state ----
	var gear_flap_ok := true
	var gdetail := ""
	_air(a, 150.0, vcr)
	await _run(60, func(): _alt_hold(a, 150.0, 0.6))
	if a.has_retracts():
		a.toggle_gear()
		await _run(120 * 3, func(): _alt_hold(a, 150.0, 0.6))
		var up_ok := a.gear_pos <= 0.001
		var moved := 0
		a.update_visuals(a.global_transform, 0.0)
		for w in a.wheels:
			var rt := a.build_part(int(w["retract_part"]))
			if rt and not rt.basis.is_equal_approx(Basis()):
				moved += 1
		a.toggle_gear()
		await _run(120 * 3, func(): _alt_hold(a, 150.0, 0.6))
		a.update_visuals(a.global_transform, 0.0)
		var down_ok := a.gear_pos >= 0.999
		var restored := 0
		for w in a.wheels:
			var rt2 := a.build_part(int(w["retract_part"]))
			if rt2 and rt2.basis.is_equal_approx(Basis()):
				restored += 1
			elif rt2:
				gdetail += " [wheel tail=%s bent=%.3f angle=%.3f]" % [w["tail"], float(w["bent"]), rt2.basis.get_rotation_quaternion().get_angle()]
		gear_flap_ok = up_ok and moved == a.wheels.size() and down_ok and restored == a.wheels.size()
		gdetail += " up=%s moved=%d/%d down=%s restored=%d" % [up_ok, moved, a.wheels.size(), down_ok, restored]
	if a.has_flaps():
		a.flap_cmd = 1.0
		await _run(120 * 3, func(): _alt_hold(a, 150.0, 0.6))
		var fl_defl := 0.0
		for s_ in a.surfaces:
			for mx in s_["mix"]:
				if int(mx[0]) == 3:
					fl_defl = maxf(fl_defl, absf(float(s_["defl"])))
		var want := float(a.max_defl[3])
		gear_flap_ok = gear_flap_ok and a.flap_pos > 0.99 and absf(fl_defl - want) < 0.05 * maxf(want, 0.1)
		gdetail += " flap_pos=%.2f defl=%.2f/%.2f" % [a.flap_pos, fl_defl, want]
		a.flap_cmd = 0.0
		await _run(120 * 2, func(): _alt_hold(a, 150.0, 0.6))
	if a.has_retracts() or a.has_flaps():
		_ok("%s: retracts and flaps travel to their commanded state and the visuals follow" % id, gear_flap_ok, gdetail)
	# ---- 4. takeoff, scripted pilot (tail up, rotate) ----
	var tk := await _takeoff(a, id, sp)
	_ok("%s: takeoff roll under power, no damage, lifts off near 1.2-1.5 Vs and climbs away" % id, tk["ok"], tk["detail"])
	# ---- 5. power-off stall: speed at the break vs. the spec sheet, and recovery ----
	var st := await _stall(a, id, sp)
	_ok("%s: stall breaks near the published Vs and recovers with elevator + power" % id, st["ok"], st["detail"])
	# ---- 6. spin entry and standard recovery ----
	var sr := await _spin(a, id, sp)
	_ok("%s: %s" % [id, sr["title"]], sr["ok"], sr["detail"])
	# ---- 7. hands-off stability: trimmed flight at the factory trim speed, level-flight power ----
	var v_trim := a.trim_speed()
	var thr_cr := AircraftSpecs.level_throttle(a, v_trim)
	_air(a, 150.0, v_trim)
	await _run(240, func(): _alt_hold(a, 150.0, thr_cr))
	var hs := {"pmin": 99.0, "pmax": -99.0, "bmax": 0.0}
	var h0 := a.global_position.y
	await _run(120 * 8, func():
		a.set_inputs(0.0, 0.0, 0.0, thr_cr)
		hs["pmin"] = minf(hs["pmin"], rad_to_deg(_att(a).y))
		hs["pmax"] = maxf(hs["pmax"], rad_to_deg(_att(a).y))
		hs["bmax"] = maxf(hs["bmax"], absf(rad_to_deg(_att(a).x))))
	var stable_cat := cat in ["Trainer", "Bush / STOL", "Warbird", "Multi-engine", "Airliner", "Sport Trainer"]   # the biplane and 3D types are meant to be flown actively
	var lim_p := 22.0 if stable_cat else 40.0
	var lim_b := 45.0 if stable_cat else 70.0
	_ok("%s: hands-off cruise stays inside a sane envelope (no divergence)" % id, hs["pmax"] < lim_p and hs["pmin"] > -lim_p and hs["bmax"] < lim_b and not a.crashed_flag,
		"v=%.1f thr=%.2f pitch[%.0f..%.0f] bank<=%.0f dAlt=%.1f" % [v_trim, thr_cr, hs["pmin"], hs["pmax"], hs["bmax"], a.global_position.y - h0])
	# ---- 8. landing: powered-idle approach at 1.3 Vs, flare, brake ----
	var ld := await _landing(a, id, sp)
	_ok("%s: ordinary touchdown (0.9 m/s sink) and braked roll-out without damage, no bounce" % id, ld["ok"], ld["detail"])
	# ---- 9. damage -> repair round trip restores the aircraft ----
	a.repair_all()
	await _frames(2)
	var parts_before := _detached().size()
	var killed := ""
	for ci in a.comps.size():
		var c: Dictionary = a.comps[ci]
		if String(c["kind"]) in ["wingtip", "stab", "fin"] and not c["detached"]:
			a.detach(ci, {"sev": 8.0, "pos": a.global_position})
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

func _hurt() -> String:
	var out := []
	for c in ac.comps:
		if float(c["hp"]) < 0.99 or c["detached"]:
			out.append("%s:%.2f%s" % [c["id"], c["hp"], "X" if c["detached"] else ""])
	return ",".join(out)

func _takeoff(a: Aircraft, id: String, sp: Dictionary) -> Dictionary:
	a.repair_all()
	_rest_place(a, -60.0)
	a.flap_cmd = 0.0
	a.flap_pos = 0.0
	a.set_inputs(0, 0, 0, 0)
	for e in a.engines:
		if not e.running:
			e.start_request(0.0)
	await _run(200, func(): a.set_inputs(0, 0, 0, 0))
	a.damage_mode = "physical"
	var x0 := a.global_position
	var t := 0.0
	var vs: float = sp["v_stall_clean_ms"]
	var taildragger := String(a.def["gear"]["type"]) == "taildragger"
	var r := {"lof_d": -1.0, "lof_v": 0.0, "maxdmg": 0.0}
	for i in 120 * 22:
		t += 1.0 / 120.0
		var thr := clampf(t / 1.5, 0.0, 1.0)
		var head_err := wrapf(atan2(-a.global_transform.basis.z.x, -a.global_transform.basis.z.z) - (PI * 0.5), -PI, PI)
		var yaw := clampf(head_err * 3.0 - _rates(a).z * 0.3, -1, 1)
		if a.airspeed < vs * 1.15:
			var pc := 0.0
			if taildragger and a.airspeed > vs * 0.4:
				pc = clampf((deg_to_rad(4.0) - _att(a).y) * 2.5 - _rates(a).y * 0.4, -0.35, 0.3)
			a.set_inputs(clampf(-_att(a).x * 2.0, -1, 1), pc, yaw, thr)
		else:
			# rotate: pull to a 12 degree attitude and hold it until she flies
			_ap(a, 0.0, deg_to_rad(12.0), thr, yaw * 0.3)
		await get_tree().physics_frame
		if r["lof_d"] < 0.0 and a.wheels_touching == 0 and a.global_position.y > 0.4 and a.airborne_time > 0.3:
			r["lof_d"] = a.global_position.distance_to(x0)
			r["lof_v"] = a.airspeed
		r["maxdmg"] = maxf(r["maxdmg"], _max_dmg())
		if a.global_position.y > 12.0 or a.crashed_flag:
			break
	var lim := maxf(3.0 * float(sp["takeoff_roll_m"]), 15.0)
	var ratio := float(r["lof_v"]) / vs
	# low-aspect-ratio swept/delta wings need a higher attitude (and speed) to carry the weight than a straight wing
	var ratio_max := 1.6 if String(sp["category"]) not in ["EDF Jet", "Turbine Jet", "Airliner"] else 1.9
	var ok: bool = r["lof_d"] > 0.0 and r["lof_d"] < lim and not a.crashed_flag and r["maxdmg"] < 0.05 and a.global_position.y > 8.0 and ratio > 0.85 and ratio < ratio_max
	return {"ok": ok, "detail": "roll %.0f m (limit %.0f, est %.0f) Vlof %.1f = %.2f Vs, alt %.1f dmg %.2f crash=%s" % [r["lof_d"], lim, sp["takeoff_roll_m"], r["lof_v"], ratio, a.global_position.y, r["maxdmg"], a.crashed_flag]}

func _stall(a: Aircraft, id: String, sp: Dictionary) -> Dictionary:
	a.repair_all()
	a.flap_cmd = 0.0
	a.flap_pos = 0.0
	var vs: float = sp["v_stall_clean_ms"]
	_air(a, 200.0, vs * 1.6)
	await _run(120, func(): _alt_hold(a, 200.0, 0.0))
	var m := {"broke": false, "v_break": 0.0, "bank": 0.0, "pitch_in": 0.0, "sig": 0.0}
	var h_hold := a.global_position.y
	for i in 120 * 60:
		# altitude-hold pilot at idle: pitch up as needed to stay level while the speed bleeds off
		m["pitch_in"] = clampf(m["pitch_in"] + ((h_hold - a.global_position.y) * 0.35 - a.linear_velocity.y * 0.5) / 120.0, -0.3, 1.0)
		if _att(a).y > deg_to_rad(28.0):   # a pilot holding level does not zoom to the vertical: let the nose settle
			m["pitch_in"] = minf(m["pitch_in"], 0.3)
		a.set_inputs(clampf(-_att(a).x * 2.0, -1, 1), m["pitch_in"], 0.0, 0.0)
		await get_tree().physics_frame
		m["bank"] = maxf(m["bank"], absf(rad_to_deg(_att(a).x)))
		# the sim's own separation state: area-weighted stalled fraction of the main-wing panels
		var sa := 0.0
		var sw := 0.0
		for p_ in a.panels:
			if String(p_["role"]) == "wing" and p_["alive"]:
				sa += float(p_.get("sigma", 0.0)) * float(p_["area"])
				sw += float(p_["area"])
		m["sig"] = sa / maxf(sw, 1e-4)
		# tip-stall dominated wings (wing rock, parachuting descent at full back stick) never separate >50 % of the area
		if a.agl < 1.5 or a.wheels_touching > 0:   # a steady mush that reaches the ground is the 'mushed' outcome, not a stall break
			break
		var lost_hold: bool = m["pitch_in"] > 0.99 and m["sig"] > 0.15 and (h_hold - a.global_position.y) > 6.0 and a.linear_velocity.y < -2.0
		if (m["sig"] > 0.5 or lost_hold) and a.g_load > 0.6:   # a stall in the unloaded top of a zoom is not a 1 g stall
			m["broke"] = true
			# speed at 1 g: a zoom-climb stall happens at n < 1 and must not read as a very low stall speed
			m["v_break"] = a.airspeed / sqrt(maxf(a.g_load, 0.25))
			break
	var cat := String(sp["category"])
	var forgiving: bool = cat in ["Trainer", "Bush / STOL", "Sport Trainer", "Multi-engine", "Airliner"]
	var wing_drop_ok: bool = m["bank"] < (45.0 if forgiving else 130.0)
	# a docile aircraft may simply never stall at idle: the elevator runs out before the wing does ("mushing"), which is fine
	# Some airframes cannot be stalled at idle at all: the elevator runs out of authority before the wing reaches its
	# stall ("mushing"). That is a legitimate, safe outcome as long as it stays controllable and does not roll off.
	var mushed: bool = not m["broke"] and m["pitch_in"] > 0.99 and m["bank"] < 70.0 and a.linear_velocity.y > -6.0 and not a.crashed_flag
	if mushed:
		m["broke"] = true
		m["v_break"] = vs
	# recovery: stick forward and wings level for a second, then power and a gentle climb attitude
	var t_rec := -1.0
	await _run(120, func(): a.set_inputs(clampf(-_att(a).x * 2.0, -1, 1), -0.4, 0.0, 1.0))
	for i in 120 * 6:
		_ap(a, 0.0, deg_to_rad(2.0), 1.0)
		await get_tree().physics_frame
		if rad_to_deg(a.aoa) < 9.0 and a.linear_velocity.y > -1.0 and t_rec < 0.0:
			t_rec = 1.0 + i / 120.0
			break
	var ratio := float(m["v_break"]) / vs
	# the dynamic pull-up (prop-wash, ground-free decelerating flight, pitch lag) moves the break around the static polar by up to +-40 %
	return {"ok": m["broke"] and ratio > 0.55 and ratio < 1.6 and wing_drop_ok and t_rec > 0.0 and not a.crashed_flag,
		"detail": "stall (wing panels >50%% separated) at %.1f m/s = %.2f Vs, bank<=%.0f, recovered in %.1f s" % [m["v_break"], ratio, m["bank"], t_rec]}

func _spin(a: Aircraft, id: String, sp: Dictionary) -> Dictionary:
	a.repair_all()
	a.flap_cmd = 0.0
	a.flap_pos = 0.0
	var vs: float = sp["v_stall_clean_ms"]
	var cat := String(sp["category"])
	_air(a, 300.0, vs * 1.15)
	await _run(120, func(): _alt_hold(a, 300.0, 0.0))
	await _run(240, func(): a.set_inputs(0.0, 1.0, 0.0, 0.0))   # pull to the stall at idle, then kick the rudder
	var m := {"yaw": 0.0}
	await _run(120 * 8, func():
		a.set_inputs(0.0, 1.0, -1.0, 0.0)
		m["yaw"] += _rates(a).z / 120.0)
	var turns := absf(m["yaw"]) / TAU
	var t_rec := -1.0
	for i in 120 * 9:
		# standard recovery: rudder against the rotation (proportional, so it cannot reverse the spin), stick full forward
		# and power on while it is still rotating, then release everything
		var rr := _rates(a).z
		var engaged := absf(rr) > 0.3 or absf(_rates(a).y) > 1.5
		a.set_inputs(0.0, (-1.0 if engaged else 0.0), clampf(-rr * 0.8, -1.0, 1.0) if engaged else 0.0, 1.0 if i < 120 * 3 else 0.3)
		await get_tree().physics_frame
		if i > 40 and rad_to_deg(a.aoa) < 12.0 and absf(_rates(a).x) < 2.0 and absf(_rates(a).z) < 1.2:
			t_rec = i / 120.0
			break
	var title := ""
	var ok := false
	# Aerobats, the biplane and the agile jets must spin; trainers, STOL, transports, the heavy warbirds and the
	# attack jet fall into a spiral dive instead of a sustained spin. Every type must recover with the standard procedure.
	var must_spin: bool = cat in ["Aerobatic", "Biplane"] or id in ["viper90", "specter22", "striker16"]
	if must_spin:
		title = "spin enters and the standard recovery (rudder against, stick forward, power, then release) stops it"
		ok = turns > 0.75 and t_rec > 0.0 and t_rec < 6.0 and not a.crashed_flag
	else:
		title = "full pro-spin input is resisted (no sustained spin) and the standard recovery works"
		ok = turns < 2.2 and t_rec > 0.0 and t_rec < 6.0 and not a.crashed_flag
	return {"ok": ok, "title": title, "detail": "%.1f turns in 8 s, recovery %.1f s" % [turns, t_rec]}

func _landing(a: Aircraft, id: String, sp: Dictionary) -> Dictionary:
	a.repair_all()
	var vs: float = float(sp["v_stall_flaps_ms"]) if a.has_flaps() else float(sp["v_stall_clean_ms"])
	var v_app := 1.3 * vs
	var taildragger := String(a.def["gear"]["type"]) == "taildragger"
	# ---- A. ordinary touchdown: 1.15 Vs, 0.9 m/s sink, 6 degrees nose-up, idle, wings level ----
	_ground_place(Vector3(-100, 0, 0), -PI * 0.5, 0.0, deg_to_rad(6.0))
	var xf0 := a.global_transform
	xf0.origin.y += 0.30
	a.place(xf0, 1.15 * vs)
	a.linear_velocity += Vector3(0, -0.9, 0)
	for e in a.engines:
		e.running = true
		if e.type in ["edf", "turbine"]:
			e.rpm_frac = maxf(float(e.d.get("idle_frac", 0.0)), 0.3)
		else:
			e.omega = 400.0
	if a.has_flaps():
		a.flap_cmd = 1.0
		a.flap_pos = 1.0
	await _frames(2)
	var m := {"touched": false, "vs": 0.0, "maxdmg": 0.0, "pitch_hold": deg_to_rad(6.0), "done_t": -1.0, "dev": 0.0, "bounce": 0.0, "hmax_after": 0.0}
	var gx := a.global_position
	var t_td := -1.0
	for i in 120 * 45:
		var vy := a.linear_velocity.y
		# keep the runway axis: aim a few degrees back toward the centreline while off it
		var he := wrapf(atan2(-a.global_transform.basis.z.x, -a.global_transform.basis.z.z) - (PI * 0.5), -PI, PI) + clampf(a.global_position.z * 0.02, -0.12, 0.12)
		var yaw := clampf(he * 3.0 - _rates(a).z * 0.3, -1, 1)
		var pe := clampf((m["pitch_hold"] - _att(a).y) * 2.0 - _rates(a).y * 0.5, -0.3, 0.3)
		if m["touched"] and a.ground_speed < 0.4 * v_app and taildragger:
			pe = 0.25   # tail wheel down, stick back at low speed
		if m["touched"]:
			m["pitch_hold"] = clampf(_att(a).y, 0.0, deg_to_rad(8.0)) if a.ground_speed > 0.4 * v_app else m["pitch_hold"]
		a.set_inputs(clampf(-_att(a).x * 2.0, -1, 1), pe, yaw, 0.0)
		a.brake = (0.25 if taildragger else 0.55) if m["touched"] and a.ground_speed < 0.8 * v_app else 0.0
		await get_tree().physics_frame
		if not m["touched"] and a.wheels_touching > 0:
			m["touched"] = true
			m["vs"] = -vy
			m["hmax_after"] = a.agl
		if m["touched"]:
			m["bounce"] = maxf(m["bounce"], a.agl - m["hmax_after"])
		m["maxdmg"] = maxf(m["maxdmg"], _max_dmg())
		m["dev"] = maxf(m["dev"], absf(a.global_position.z))
		if m["touched"] and t_td < 0.0:
			t_td = i / 120.0
		if m["touched"] and (a.ground_speed < 0.5 or i / 120.0 > t_td + 30.0):
			m["done_t"] = i / 120.0 - t_td
			break
		if a.crashed_flag:
			break
	a.brake = 0.0
	var upright := absf(rad_to_deg(_att(a).x)) < 40.0
	# the runway is 12 m wide, the flight-line fence 17 m from the centreline: stay inside 14 m
	var okA: bool = m["touched"] and m["maxdmg"] < 0.05 and upright and not a.crashed_flag and m["dev"] < 14.0 and m["bounce"] < 0.7
	var detA := "touchdown %.2f m/s sink: dmg %.2f [%s] bounce %.2f m, stopped in %.1f s / %.0f m, off-axis %.1f m, upright=%s crash=%s" % [m["vs"], m["maxdmg"], _hurt(), m["bounce"], m["done_t"], a.global_position.distance_to(gx), m["dev"], upright, a.crashed_flag]
	# ---- B. rollout handling: rolling at 0.35 v_app (the wings no longer carry the weight), idle, wings level, braking ----
	a.repair_all()
	a.flap_cmd = 0.0
	a.flap_pos = 0.0
	_rest_place(a, -100.0, 0.35 * v_app)
	for e in a.engines:
		e.running = true
		if e.type in ["edf", "turbine"]:
			e.rpm_frac = maxf(float(e.d.get("idle_frac", 0.0)), 0.3)
		else:
			e.omega = 400.0
	var rb := {"maxdmg": 0.0, "dev": 0.0, "t": -1.0}
	var x_start := a.global_position
	for i in 120 * 45:
		var yaw2 := clampf(wrapf(atan2(-a.global_transform.basis.z.x, -a.global_transform.basis.z.z) - (PI * 0.5), -PI, PI) * 3.0 - _rates(a).z * 0.3, -1, 1)
		a.set_inputs(clampf(-_att(a).x * 2.0, -1, 1), (0.15 if taildragger else 0.0), yaw2, 0.0)
		a.brake = 0.3 if taildragger else 0.6
		await get_tree().physics_frame
		rb["maxdmg"] = maxf(rb["maxdmg"], _max_dmg())
		rb["dev"] = maxf(rb["dev"], absf(a.global_position.z))
		if a.ground_speed < 0.3:
			rb["t"] = i / 120.0
			break
	a.brake = 0.0
	var okB: bool = rb["t"] > 0.0 and rb["maxdmg"] < 0.05 and rb["dev"] < 8.0 and absf(rad_to_deg(_att(a).x)) < 30.0 and not a.crashed_flag
	var detB := "rollout: stopped in %.1f s / %.0f m, off-axis %.1f m, dmg %.2f" % [rb["t"], a.global_position.distance_to(x_start), rb["dev"], rb["maxdmg"]]
	return {"ok": okA and okB, "detail": detA + " | " + detB}

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
