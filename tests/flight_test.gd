extends Node3D
## Headless flight-model test bench. Run:
##   godot --headless --fixed-fps 120 --path . res://tests/flight_test.tscn -- [aircraft_id|all] [test]
## Prints measured performance so the data can be checked against real RC numbers.

var ground: StaticBody3D
var ac: Aircraft
var results = []
var only := ""
var which := "all"

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	only = args[0] if args.size() > 0 else "all"
	which = args[1] if args.size() > 1 else "all"
	Engine.max_physics_steps_per_frame = 1
	_make_ground()
	Game.wind = Wind.new()
	Game.wind.configure("calm", "headwind", Vector3(1, 0, 0))
	await get_tree().process_frame
	var ids = AircraftDB.ids() if only == "all" else PackedStringArray([only])
	for id in ids:
		await _run_aircraft(id)
	print("DONE")
	get_tree().quit()

func _make_ground() -> void:
	ground = StaticBody3D.new()
	ground.collision_layer = Game.L_WORLD
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(4000, 2, 4000)
	cs.shape = bs
	cs.position = Vector3(0, -1, 0)
	ground.add_child(cs)
	ground.set_meta("surface", Game.SURF_ASPHALT)
	add_child(ground)

func _spawn(id: String) -> Aircraft:
	if ac:
		ac.queue_free()
		await get_tree().physics_frame
	var a := Aircraft.new()
	a.setup(AircraftDB.by_id(id), Settings.aircraft_cfg(id), 0, false)
	a.assist = "expert"
	add_child(a)
	ac = a
	return a

func _ground_xf(a: Aircraft) -> Transform3D:
	var low := 0.0
	for w in a.wheels:
		low = minf(low, (w["center"] as Vector3).y - float(w["r"]))
	# taildragger sits tail down: rotate so all wheels touch
	var xf := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(0, -low + 0.005, 0))
	if String(a.def["gear"]["type"]) == "taildragger":
		var main: Dictionary = a.wheels[0]
		var tail: Dictionary = a.wheels[a.wheels.size() - 1]
		var mz := (main["center"] as Vector3).z
		var tz := (tail["center"] as Vector3).z
		var my := (main["center"] as Vector3).y - float(main["r"])
		var ty := (tail["center"] as Vector3).y - float(tail["r"])
		var ang := atan2(ty - my, tz - mz)   # rotate nose up
		var b := Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3.RIGHT, ang)
		var tmp := Transform3D(b, Vector3.ZERO)
		var lowy := 0.0
		for w in a.wheels:
			lowy = minf(lowy, (tmp * ((w["center"] as Vector3) - Vector3(0, float(w["r"]), 0))).y)
		xf = Transform3D(b, Vector3(0, -lowy + 0.005, 0))
	return xf

func _att(a: Aircraft) -> Vector3:
	var B := a.global_transform.basis
	var bank := atan2(-B.x.y, B.y.y)
	var pitch := asin(clampf(-B.z.y, -1, 1))
	var w_l := B.transposed() * a.angular_velocity
	return Vector3(bank, pitch, 0) if true else w_l

func _rates(a: Aircraft) -> Vector3:
	var w_l := a.global_transform.basis.transposed() * a.angular_velocity
	return Vector3(-w_l.z, w_l.x, -w_l.y)  # p, q, r

func _ap(a: Aircraft, tb: float, tp: float, thr: float, yaw := 0.0) -> void:
	var at := _att(a)
	var r := _rates(a)
	var kq := clampf(20.0 / maxf(a.airspeed, 5.0), 0.2, 2.0)
	var roll := clampf((tb - at.x) * 2.0 * kq - r.x * 0.25 * kq, -1, 1)
	var pitch := clampf((tp - at.y) * 3.0 * kq - r.y * 0.5 * kq, -1, 1)
	a.set_inputs(roll, pitch, yaw, thr)

func _alt_hold(a: Aircraft, h0: float, thr: float) -> void:
	var vs := a.linear_velocity.y
	var tp := clampf((h0 - a.global_position.y) * 0.04 - vs * 0.08, -0.35, 0.35)
	_ap(a, 0.0, tp, thr)

func _steps(n: int, cb: Callable) -> void:
	for i in n:
		cb.call()
		await get_tree().physics_frame

func _start_engines(a: Aircraft) -> void:
	for e in a.engines:
		if not e.running:
			e.start_request(0.0)

func _air_spawn(a: Aircraft, h: float, v: float) -> void:
	var xf := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(0, h, 0))
	a.place(xf, v)
	for e in a.engines:
		e.running = true
		if e.type in ["edf", "turbine"]:
			e.rpm_frac = 0.6
		else:
			e.omega = 600.0

func _run_aircraft(id: String) -> void:
	var a: Aircraft = await _spawn(id)
	var d := a.def
	var S := a.ref_area
	var vs_est := sqrt(2.0 * a.mass * 9.81 / (1.225 * S * 1.25))
	var line = "%-11s m=%.2fkg WL=%.1fkg/m2 Vs_est=%.1f" % [id, a.mass, a.mass / S, vs_est]
	# ---- rest ----
	if which in ["all", "rest", "takeoff"]:
		var gx := _ground_xf(a)
		a.place(gx)
		await _steps(240, func(): a.set_inputs(0, 0, 0, 0))
		var comp = []
		for w in a.wheels:
			comp.append("%.0f%%" % (float(w["comp_now"]) / float(w["len"]) * 100.0))
		var att := _att(a)
		if OS.get_environment("FTDBG") != "":
			for w in a.wheels:
				var cw: Vector3 = a.global_transform * (w["center"] as Vector3)
				print("   wheel tail=%s bottom_y=%.3f travel=%.3f comp=%.4f" % [w["tail"], cw.y - float(w["r"]), w["travel"], w["comp_now"]])
			for ch in a.get_children():
				if ch is CollisionShape3D and (ch as CollisionShape3D).shape != null and not (ch as CollisionShape3D).disabled:
					var cs := ch as CollisionShape3D
					var low := 99.0
					var sh = cs.shape
					var pts := []
					if sh is BoxShape3D:
						var e = sh.size * 0.5
						for sx in [-1, 1]:
							for sy in [-1, 1]:
								for sz in [-1, 1]:
									pts.append(Vector3(e.x * sx, e.y * sy, e.z * sz))
					elif sh is SphereShape3D:
						low = (a.global_transform * cs.transform).origin.y - sh.radius
					for pp in pts:
						low = minf(low, (a.global_transform * cs.transform * pp).y)
					if low < 0.06:
						print("   shape ", cs.name, " ", sh.get_class(), " low=%.3f" % low)
		line += " | rest vy=%.3f pitch=%.1f comp=%s dmg=%s" % [a.linear_velocity.y, rad_to_deg(att.y), str(comp), str(a.max_impact).left(4)]
	# ---- takeoff ----
	if which in ["all", "takeoff"]:
		_start_engines(a)
		await _steps(200, func(): a.set_inputs(0, 0, 0, 0))
		var t := 0.0
		var x0 := a.global_position
		var lof_v := -1.0
		var lof_d := -1.0
		var rot_v := vs_est * 1.15
		var taildragger := String(d["gear"]["type"]) == "taildragger"
		var yaw_i := 0.0
		for i in 120 * 25:
			t += 1.0 / 120.0
			var thr := clampf(t / 1.5, 0.0, 1.0)
			var head_err := wrapf(atan2(-a.global_transform.basis.z.x, -a.global_transform.basis.z.z) - (PI * 0.5), -PI, PI)
			var yaw := clampf(-head_err * 3.0 - _rates(a).z * 0.3, -1, 1)
			if a.airspeed < rot_v:
				var pc := 0.0
				if taildragger and a.airspeed > vs_est * 0.4:
					# raise the tail to a slightly nose-up attitude, like a pilot would
					pc = clampf((deg_to_rad(4.0) - _att(a).y) * 2.5 - _rates(a).y * 0.4, -0.35, 0.3)
				_ap(a, 0.0, 0.0, thr, 0.0)
				a.set_inputs(clampf(-_att(a).x * 2.0, -1, 1), pc, yaw, thr)
			else:
				_ap(a, 0.0, deg_to_rad(10.0), thr, yaw * 0.3)
			await get_tree().physics_frame
			if OS.get_environment("FTDBG") != "" and i % 60 == 0:
				print("  t=%.1f spd=%.1f pos=%s pitch=%.1f bank=%.1f wt=%d thr=%.2f rpm=%.0f hdg_err=%.2f crashed=%s" % [t, a.airspeed, str(a.global_position), rad_to_deg(_att(a).y), rad_to_deg(_att(a).x), a.wheels_touching, thr, a.engines[0].rpm(), head_err, a.crashed_flag])
				var dm = []
				for c in a.health_summary():
					if float(c["hp"]) < 0.99 or c["detached"]: dm.append("%s:%.2f%s" % [c["id"], c["hp"], "X" if c["detached"] else ""])
				var ws = []
				for w in a.wheels: ws.append("%d" % int(w["contact"]))
				print("     dmg=", dm, " wheels=", ws, " yawin=%.2f" % yaw)
			if lof_v < 0.0 and a.wheels_touching == 0 and a.global_position.y > 0.3 and a.airborne_time > 0.2:
				lof_v = a.airspeed
				lof_d = a.global_position.distance_to(x0)
			if a.global_position.y > 25.0 or a.crashed_flag:
				break
		line += " | takeoff Vlof=%.1f dist=%.0fm t=%.1fs alt=%.0f crash=%s" % [lof_v, lof_d, t, a.global_position.y, a.crashed_flag]
	print(line)
	line = "            "
	if which in ["all", "perf"]:
		# ---- max speed ----
		a.repair_all()
		_air_spawn(a, 60.0, vs_est * 2.0)
		await _steps(120 * 15, func(): _alt_hold(a, 60.0, 1.0))
		var vmax := a.airspeed
		var rpm = a.telemetry()["rpm"]
		var amps := a.total_current
		# ---- cruise 50% ----
		await _steps(120 * 12, func(): _alt_hold(a, 60.0, 0.5))
		var vcr := a.airspeed
		var aoa_cr := rad_to_deg(a.aoa)
		# ---- stall: idle + hold altitude ----
		var vmin := 999.0
		var stalled_at := -1.0
		for i in 120 * 20:
			_alt_hold(a, 60.0, 0.0)
			await get_tree().physics_frame
			if a.global_position.y > 55.0:
				vmin = minf(vmin, a.airspeed)
			if stalled_at < 0.0 and a.global_position.y < 57.0:
				stalled_at = a.airspeed
				break
		line += "Vmax=%.1f (%.0f rpm %.0fA) Vcruise50=%.1f aoa=%.1f  Vmin(level)=%.1f" % [vmax, rpm, amps, vcr, aoa_cr, vmin]
		# ---- roll rate ----
		_air_spawn(a, 60.0, maxf(vcr, vs_est * 1.8))
		await _steps(120, func(): _alt_hold(a, 60.0, 0.6))
		var p_max := 0.0
		for i in 120:
			a.set_inputs(1.0, 0.0, 0.0, 0.6)
			await get_tree().physics_frame
			p_max = maxf(p_max, _rates(a).x)
		line += " roll=%.0fdeg/s" % rad_to_deg(p_max)
		# ---- hands-off stability at 60% ----
		_air_spawn(a, 60.0, vcr)
		await _steps(120 * 2, func(): _alt_hold(a, 60.0, 0.6))
		var hy0 := a.global_position.y
		var ho_min := 999.0
		var ho_max := -999.0
		for i in 120 * 8:
			a.set_inputs(0.0, 0.0, 0.0, 0.6)
			await get_tree().physics_frame
			ho_min = minf(ho_min, rad_to_deg(_att(a).y))
			ho_max = maxf(ho_max, rad_to_deg(_att(a).y))
		line += " handsoff8s dAlt=%.1f pitch[%.0f..%.0f] bank=%.0f" % [a.global_position.y - hy0, ho_min, ho_max, rad_to_deg(_att(a).x)]
		# ---- loop ----
		_air_spawn(a, 80.0, maxf(vmax * 0.9, vs_est * 2.0))
		await _steps(60, func(): _alt_hold(a, 80.0, 1.0))
		var pitch_acc := 0.0
		var looped := false
		for i in 120 * 6:
			a.set_inputs(0.0, 1.0, 0.0, 1.0)
			await get_tree().physics_frame
			pitch_acc += _rates(a).y / 120.0
			if pitch_acc > TAU:
				looped = true
				break
		line += " loop=%s(%.0fdeg)" % [looped, rad_to_deg(pitch_acc)]
		print(line)
		line = "            "
	if which in ["all", "spin"]:
		# ---- spin ----
		a.repair_all()
		_air_spawn(a, 120.0, vs_est * 1.3)
		await _steps(60, func(): _alt_hold(a, 120.0, 0.0))
		await _steps(150, func(): a.set_inputs(0.0, 1.0, 0.0, 0.0))
		var yaw_acc := 0.0
		var alt0 := a.global_position.y
		for i in 120 * 6:
			a.set_inputs(0.0, 1.0, -1.0, 0.0)
			await get_tree().physics_frame
			yaw_acc += _rates(a).z / 120.0
		var turns := absf(yaw_acc) / TAU
		var sink := (alt0 - a.global_position.y) / 6.0
		var rec_t := -1.0
		for i in 120 * 8:
			a.set_inputs(0.0, -0.3, 1.0 if i < 120 else 0.0, 0.0)
			await get_tree().physics_frame
			if absf(_rates(a).z) < 0.3 and i > 60:
				rec_t = i / 120.0
				break
		line += "spin: %.1f turns/6s sink=%.1fm/s recovery=%.1fs" % [turns, sink, rec_t]
		# ---- knife edge ----
		_air_spawn(a, 100.0, maxf(vs_est * 2.6, 15.0))
		await _steps(120, func(): _alt_hold(a, 100.0, 1.0))
		var h0 := a.global_position.y
		for i in 120 * 4:
			var at := _att(a)
			var r := _rates(a)
			var roll := clampf((deg_to_rad(90.0) - at.x) * 2.0 - r.x * 0.2, -1, 1)
			var vs := a.linear_velocity.y
			var yaw := clampf(vs * 0.25 + (a.global_position.y - h0) * 0.08, -1, 1)
			a.set_inputs(roll, 0.0, yaw, 1.0)
			await get_tree().physics_frame
		line += " | knife-edge 4s: dAlt=%.1fm" % (a.global_position.y - h0)
		print(line)
