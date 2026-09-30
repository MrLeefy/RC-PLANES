extends Node
## Automated QA suite. Run headless:
##   godot --headless --fixed-fps 120 --path . -- --test
## Builds the real field (all colliders) and runs collision/damage/replay/save tests.

var field: Field
var fx: Fx
var results: Array = []
var ac: Aircraft
var holder: Node3D

func _ready() -> void:
	Engine.max_physics_steps_per_frame = 1
	print("=== RC PARK TEST SUITE ===")
	Game.wind = Wind.new()
	Game.wind.configure("calm", "headwind", Vector3(1, 0, 0))
	holder = Node3D.new()
	add_child(holder)
	field = Field.new()
	holder.add_child(field)
	Game.field = field
	await field.build_async("high", func(_f, _t): pass)
	fx = Fx.new()
	holder.add_child(fx)
	fx.setup()
	Game.fx = fx
	await _frames(5)
	await _run_all()
	_report()
	get_tree().quit(0 if _all_pass() else 1)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ok(name: String, pass_: bool, detail := "") -> void:
	results.append({"test": name, "pass": pass_, "detail": detail})
	print(("PASS  " if pass_ else "FAIL  ") + name + ("  -- " + detail if detail != "" else ""))

func _all_pass() -> bool:
	for r in results:
		if not r["pass"]:
			return false
	return true

func _spawn(id: String, damage := "physical") -> Aircraft:
	if ac and is_instance_valid(ac):
		ac.queue_free()
		await _frames(2)
	fx.clear_chips()
	ac = Aircraft.new()
	ac.setup(AircraftDB.by_id(id), Settings.aircraft_cfg(id), 0, false)
	ac.assist = "expert"
	ac.damage_mode = damage
	holder.add_child(ac)
	await _frames(1)
	return ac

func _detached() -> Array:
	var out := []
	for c in ac.comps:
		if c["detached"]:
			out.append(c["id"])
	return out

func _max_dmg() -> float:
	var m := 0.0
	for c in ac.comps:
		m = maxf(m, 1.0 - float(c["hp"]))
	return m

func _ground_place(pos: Vector3, yaw: float, roll := 0.0, pitch := 0.0, speed := 0.0) -> void:
	var low := 0.0
	for w in ac.wheels:
		low = minf(low, (w["center"] as Vector3).y - float(w["r"]))
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, roll) * Basis(Vector3.RIGHT, pitch)
	var p := pos
	p.y = field.ground_y(pos) - low + 0.02
	ac.place(Transform3D(b, p), speed)

func _run_all() -> void:
	await t_linear_curve()
	await t_save_migration()
	await t_rest_on_gear()
	await t_normal_touchdown()
	await t_slow_wingtip_scrape()
	await t_tilted_stationary()
	await t_prop_strike()
	await t_hard_tree_wing()
	await t_tunnel_trunk()
	await t_building()
	await t_table()
	await t_parked_aircraft()
	await t_person()
	await t_bush_drag()
	await t_fence_net()
	await t_debris_secondary()
	await t_damage_changes_flight()
	await t_rewind_snapshot()
	await t_replay_buffer()
	await t_repeated_crashes()
	await t_all_aircraft_spawn()

# ---------------------------------------------------------------- unit-ish
func t_linear_curve() -> void:
	var lin: Dictionary = Settings.TX_PRESETS["Linear / Direct"]["roll"]
	var ok := true
	for x in [-1.0, -0.5, -0.1, 0.0, 0.07, 0.3, 1.0]:
		if absf(Transmitter.shape(x, lin) - x) > 1e-6:
			ok = false
	_ok("transmitter: Linear preset is exactly linear", ok)
	var g: Dictionary = Settings.TX_PRESETS["Gentle"]["roll"]
	_ok("transmitter: expo softens centre", absf(Transmitter.shape(0.3, g)) < 0.3 * 0.75)

func t_save_migration() -> void:
	var saved := Settings.data.duplicate(true)
	var v1 := {"version": 1, "tx": {"expo": 0.0, "rate": 0.8}, "gameplay": {"difficulty": "hard", "aftermath": 0}, "graphics": {"grass": 0.0}}
	var m := Settings.migrate(v1.duplicate(true))
	var merged := Settings.deep_merge(Settings.defaults(), m)
	var ok: bool = merged["gameplay"]["assist"] == "expert" and float(merged["transmitter"]["profiles"]["Migrated"]["roll"]["expo"]) == 0.0
	ok = ok and float(merged["graphics"]["grass"]) == 0.0 and int(merged["gameplay"]["aftermath"]) == 0
	_ok("save: v1->v3 migration keeps zero values", ok, str(merged["gameplay"]))
	# corrupted file with no recovery candidate; backup recovery has its own test.
	for suffix in [".bak", ".tmp"]:
		if FileAccess.file_exists(Settings.SAVE_PATH + suffix): DirAccess.remove_absolute(Settings.SAVE_PATH + suffix)
	var f := FileAccess.open(Settings.SAVE_PATH, FileAccess.WRITE)
	f.store_string("{ this is not json ")
	f.close()
	Settings.load_settings()
	_ok("save: corrupted file falls back to defaults", Settings.load_status == "corrupt_reset" and Settings.data.has("transmitter"))
	Settings.data = saved
	Settings.save()

# ---------------------------------------------------------------- ground handling
func t_rest_on_gear() -> void:
	for id in ["skylark", "tundra_cub", "viper90", "skyliner"]:
		await _spawn(id)
		_ground_place(Vector3(-40, 0, 0), -PI * 0.5)
		if String(ac.def["gear"]["type"]) == "taildragger":
			_ground_place(Vector3(-40, 0, 0), -PI * 0.5, 0.0, 0.18)
		ac.brake = 1.0
		await _frames(240)
		_ok("rest on gear: %s settles without damage" % id, _max_dmg() < 0.05 and not ac.crashed_flag and ac.linear_velocity.length() < 0.05, "vel=%.3f dmg=%.2f" % [ac.linear_velocity.length(), _max_dmg()])

func t_normal_touchdown() -> void:
	await _spawn("skylark")
	var p := Vector3(-30, 0.5, 0)
	ac.place(Transform3D(Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3.RIGHT, deg_to_rad(4.0)), p), 11.0)
	ac.linear_velocity += Vector3(0, -1.3, 0)
	await _frames(360)
	var pk0 := []
	for w in ac.wheels:
		pk0.append(snappedf(float(w.get("last_peak_g", 0.0)), 0.1))
	_ok("landing gear absorbs ordinary touchdown (1.3 m/s sink)", not ac.crashed_flag and _detached().is_empty() and _max_dmg() < 0.2, "dmg=%.2f det=%s peak_load_ratio=%s" % [_max_dmg(), _detached(), pk0])
	# hard landing loads the gear (bends) before failing
	await _spawn("skylark")
	ac.place(Transform3D(Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3.RIGHT, deg_to_rad(5.0)), Vector3(-30, 0.45, 0)), 10.0)
	ac.linear_velocity += Vector3(0, -3.6, 0)
	await _frames(240)
	var bent := 0.0
	var pk := []
	for w in ac.wheels:
		bent = maxf(bent, float(w["bent"]))
		pk.append(snappedf(float(w.get("last_peak_g", 0.0)), 0.1))
	_ok("hard landing (3.6 m/s sink) loads/bends gear but airframe survives", not ac.crashed_flag and bent > 0.0, "bent=%.2f det=%s peak_load_ratio=%s" % [bent, _detached(), pk])

func t_slow_wingtip_scrape() -> void:
	await _spawn("skylark")
	_ground_place(Vector3(-50, 0, 3), -PI * 0.5, deg_to_rad(14.0), 0.0, 2.0)
	await _frames(240)
	_ok("slow wingtip scrape does NOT trigger a crash", not ac.crashed_flag and _detached().is_empty(), "dmg=%.2f" % _max_dmg())

func t_tilted_stationary() -> void:
	await _spawn("aerostar")
	_ground_place(Vector3(-50, 0, -3), -PI * 0.5, deg_to_rad(22.0), deg_to_rad(10.0), 0.0)
	await _frames(300)
	_ok("stationary tilted aircraft touching a wing does not break", not ac.crashed_flag and _detached().is_empty() and _max_dmg() < 0.25, "dmg=%.2f crashed=%s det=%s" % [_max_dmg(), ac.crashed_flag, _detached()])

func t_prop_strike() -> void:
	await _spawn("tundra_cub")
	# engine running, dropped nose-first from a few cm: only the prop disc reaches the grass
	var b := Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3.RIGHT, deg_to_rad(-55.0))
	var e0: Propulsion = ac.engines[0]
	var R := e0.D * 0.5
	var tip_low := (b * (e0.pos + Vector3(0, -R, 0))).y
	ac.place(Transform3D(b, Vector3(-20, -tip_low + 0.12, -3)), 0.0)
	for e in ac.engines:
		e.running = true
		e.omega = 900.0
	var prop_hit := false
	for i in 150:
		ac.set_inputs(0, 0, 0, 0.5)
		await get_tree().physics_frame
		for c in ac.comps:
			if String(c["kind"]) == "prop" and (float(c["hp"]) < 0.98 or c["detached"]):
				prop_hit = true
	var other := _detached().filter(func(x): return not String(x).begins_with("prop"))
	_ok("prop strike stays localised (prop damaged, airframe intact)", prop_hit and not ac.crashed_flag and other.is_empty(), "prop_hit=%s detached=%s crashed=%s" % [prop_hit, _detached(), ac.crashed_flag])

# ---------------------------------------------------------------- scenery collisions
func _fly_into(id: String, from: Vector3, to: Vector3, speed: float, frames := 240, top_y := 99.0) -> Dictionary:
	await _spawn(id)
	var dirv := (to - from).normalized()
	var yaw := atan2(-dirv.x, -dirv.z)
	ac.place(Transform3D(Basis(Vector3.UP, yaw), from), speed)
	for e in ac.engines:
		e.running = true
	var passed := false
	var plane_d := (to - from).length()
	var prev_along := 0.0
	var cross_y := -1.0
	for i in frames:
		ac.set_inputs(0, 0, 0, 0.6)
		await get_tree().physics_frame
		var cpos := ac.global_transform * ac.com_local
		var along := (cpos - from).dot(dirv)
		if prev_along < plane_d + 0.3 and along >= plane_d + 0.3 and cross_y < 0.0:
			cross_y = cpos.y
			if cross_y < top_y:
				passed = true
		prev_along = along
	return {"passed_through": passed, "cross_y": snappedf(cross_y, 0.01), "crashed": ac.crashed_flag, "det": _detached(), "dmg": snappedf(_max_dmg(), 0.01), "impact": snappedf(ac.max_impact, 0.1)}

func t_hard_tree_wing() -> void:
	# hero oak trunk at (88, 0, -46): aim the left wing at it
	var r := await _fly_into("skylark", Vector3(88 + 0.55, 2.0, -46 + 8), Vector3(88 + 0.55, 2.0, -46), 18.0, 150)
	_ok("high-speed wing vs tree: wing damaged/detached", float(r["dmg"]) > 0.5 or not (r["det"] as Array).is_empty(), str(r))

func t_tunnel_trunk() -> void:
	var r := await _fly_into("striker16", Vector3(88, 2.4, -46 + 12), Vector3(88, 2.4, -46), 60.0, 90, 5.0)
	_ok("60 m/s jet cannot tunnel through a tree trunk", not r["passed_through"], str(r))

func t_building() -> void:
	# clubhouse west wall at x = 40.5 (z 30..38, roof ~3 m): approach from 9 m out
	var r := await _fly_into("viper90", Vector3(31.0, 1.8, 35.0), Vector3(41.0, 1.8, 35.0), 35.0, 120, 3.0)
	_ok("aircraft cannot fly through the clubhouse", not r["passed_through"] and float(r["impact"]) > 5.0, str(r))

func t_table() -> void:
	var r := await _fly_into("tundra_cub", Vector3(-45, 0.8, 32.0), Vector3(-37, 0.8, 32.0), 12.0, 150, 0.8)
	_ok("aircraft cannot pass through a pit table", not bool(r["passed_through"]) and float(r["impact"]) > 2.0, str(r))

func t_parked_aircraft() -> void:
	# drop a model straight onto the parked Silver Belle: it must land ON it, not fall through
	var parked: Aircraft = field.parked[3]
	var top := parked.global_position.y + 0.25
	await _spawn("skylark")
	ac.place(Transform3D(Basis(Vector3.UP, -PI * 0.5), parked.global_transform * parked.com_local + Vector3(0, 1.2, 0)), 0.0)
	var min_y := 99.0
	for i in 150:
		await get_tree().physics_frame
		min_y = minf(min_y, (ac.global_transform * ac.com_local).y)
	_ok("aircraft cannot pass through a parked aircraft", min_y > parked.global_position.y - 0.05 and ac.max_impact > 1.0, "min_y=%.2f parked_y=%.2f impact=%.1f" % [min_y, parked.global_position.y, ac.max_impact])

func t_person() -> void:
	var n: NPC = field.npcs[0]
	n.reset_to(Vector3(-12, 0, 30))
	n.idle_t = 50.0
	n.waypoints = [Vector3(-12, 0, 30)]
	n.target = Vector3(-12, 0, 30)
	await _frames(2)
	var r := await _fly_into("vortex540", Vector3(-20, 1.1, 30), Vector3(-12, 1.1, 30), 15.0, 150, 1.8)
	_ok("aircraft collides with a person (knocked down, no pass-through)", not bool(r["passed_through"]) and n.down and float(r["impact"]) > 1.0, "npc_down=%s %s" % [n.down, str(r)])
	n.reset_to(Vector3(-30, 0, 29))

func t_bush_drag() -> void:
	# hedge behind the pits (z=43): soft volume should slow the aircraft sharply
	await _spawn("skylark")
	ac.place(Transform3D(Basis(Vector3.UP, 0.0), Vector3(-30.0, 1.0, 48.0)), 12.0)
	var v0 := 12.0
	var vmin := 99.0
	for i in 150:
		ac.set_inputs(0, 0, 0, 0)
		await get_tree().physics_frame
		if ac.global_position.z < 44.5 and ac.global_position.z > 40.0:
			vmin = minf(vmin, ac.linear_velocity.length())
	_ok("vegetation acts as soft drag (hedge slows the aircraft)", vmin < v0 * 0.75, "vmin=%.1f" % vmin)

func t_fence_net() -> void:
	var r := await _fly_into("skylark", Vector3(5, 0.7, 10.0), Vector3(5, 0.7, 16.8), 12.0, 120, 1.3)
	_ok("safety fence/netting stops the aircraft", not r["passed_through"], str(r))

# ---------------------------------------------------------------- damage & crash
func t_debris_secondary() -> void:
	await _spawn("vortex540")
	ac.place(Transform3D(Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3.RIGHT, deg_to_rad(-40.0)), Vector3(-30, 7, -30)), 30.0)
	var t0 := Time.get_ticks_usec()
	var worst := 0.0
	for i in 360:
		var a := Time.get_ticks_usec()
		await get_tree().physics_frame
		worst = maxf(worst, (Time.get_ticks_usec() - a) / 1000.0)
	var deb := ac.active_debris()
	var moved := 0
	for rb in deb:
		if (rb as RigidBody3D).global_position.distance_to(ac.global_position) > 0.5:
			moved += 1
	_ok("major crash: components detach as real rigid bodies", ac.crashed_flag and deb.size() >= 2 and moved >= 1, "debris=%d moved=%d det=%s worst_frame=%.1fms" % [deb.size(), moved, _detached(), worst])

func t_damage_changes_flight() -> void:
	await _spawn("skylark")
	ac.place(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(0, 60, 0)), 15.0)
	for e in ac.engines:
		e.running = true
	var m0 := ac.mass
	var cg0 := ac.com_local
	ac.detach(_ci("tip0_L"))
	await _frames(2)
	var roll := 0.0
	for i in 120:
		ac.set_inputs(0, 0, 0, 0.5)
		await get_tree().physics_frame
		roll += -(ac.global_transform.basis.transposed() * ac.angular_velocity).z / 120.0
	_ok("losing a wingtip changes mass, CG and makes the aircraft roll", ac.mass < m0 and ac.com_local.x > cg0.x and roll < -0.1, "dm=%.3f dcg.x=%.4f roll=%.2f rad" % [m0 - ac.mass, ac.com_local.x - cg0.x, roll])

func _ci(id: String) -> int:
	for i in ac.comps.size():
		if ac.comps[i]["id"] == id:
			return i
	return -1

func t_rewind_snapshot() -> void:
	await _spawn("skylark")
	ac.place(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(0, 30, 0)), 15.0)
	await _frames(10)
	var snap := ac.snapshot()
	ac.place(Transform3D(Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3.RIGHT, -1.2), Vector3(0, 4, 0)), 25.0)
	await _frames(200)
	var broke := _detached().size()
	ac.restore(snap)
	await _frames(2)
	_ok("rewind restores state and repairs parts broken afterwards", _detached().is_empty() and not ac.crashed_flag and absf(ac.global_position.y - 30.0) < 1.0, "broke=%d after=%s y=%.1f" % [broke, _detached(), ac.global_position.y])

func t_replay_buffer() -> void:
	await _spawn("skylark")
	var rp := Replay.new()
	holder.add_child(rp)
	rp.bind(ac, fx, field.npcs)
	ac.place(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(0, 20, 0)), 15.0)
	var t := 0.0
	for i in 600:
		await get_tree().physics_frame
		t += 1.0 / 120.0
		rp.record(t)
	rp.start(t - 3.0, t, t - 1.0)
	rp.seek(0.5)
	var mid := ac.visual_root.global_position
	rp.seek(1.0)
	var end := ac.visual_root.global_position
	rp.stop()
	_ok("replay buffer records, scrubs and restores", rp.count > 250 and mid.distance_to(end) > 5.0 and not ac.replay_driven, "frames=%d move=%.1f" % [rp.count, mid.distance_to(end)])
	rp.queue_free()

func t_repeated_crashes() -> void:
	await _spawn("skylark")
	var objs0 := 0
	var worst := []
	for k in 50:
		ac.repair_all()
		fx.clear_chips()
		ac.place(Transform3D(Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3.RIGHT, deg_to_rad(-50.0)), Vector3(-40 + (k % 5) * 6.0, 6.0, -20)), 26.0)
		var w := 0.0
		for i in 150:
			var a := Time.get_ticks_usec()
			await get_tree().physics_frame
			w = maxf(w, (Time.get_ticks_usec() - a) / 1000.0)
		worst.append(w)
		if k == 1:
			objs0 = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var objs1 := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var first := (float(worst[1]) + float(worst[2]) + float(worst[3])) / 3.0
	var last := (float(worst[47]) + float(worst[48]) + float(worst[49])) / 3.0
	_ok("50 repeated crashes: bounded object count after warm-up", objs1 - objs0 < 60, "objects %d -> %d" % [objs0, objs1])
	_ok("50 repeated crashes: no large late-run headless CPU regression", last < first * 1.6 + 2.0, "worst frame first=%.2fms last=%.2fms" % [first, last])

func t_all_aircraft_spawn() -> void:
	var bad := []
	var times := []
	for id in AircraftDB.ids():
		var t0 := Time.get_ticks_usec()
		await _spawn(id)
		times.append("%s %.0fms" % [id, (Time.get_ticks_usec() - t0) / 1000.0])
		_ground_place(Vector3(-40, 0, 0), -PI * 0.5)
		if String(ac.def["gear"]["type"]) == "taildragger":
			_ground_place(Vector3(-40, 0, 0), -PI * 0.5, 0.0, 0.18)
		await _frames(150)
		if ac.crashed_flag or not _detached().is_empty() or _max_dmg() > 0.2 or is_nan(ac.global_position.x):
			bad.append("%s(crash=%s det=%s dmg=%.2f)" % [id, ac.crashed_flag, _detached(), _max_dmg()])
	_ok("all 16 aircraft spawn and rest on their gear cleanly", bad.is_empty(), "bad=%s" % str(bad))
	print("build+spawn times: ", ", ".join(times))

func _report() -> void:
	var passed := 0
	for r in results:
		if r["pass"]:
			passed += 1
	print("=== %d / %d tests passed ===" % [passed, results.size()])
	var f := FileAccess.open("user://test_report.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))
		f.close()
	var f2 := FileAccess.open("/tmp/rcpark_test_report.json", FileAccess.WRITE)
	if f2:
		f2.store_string(JSON.stringify(results, "  "))
		f2.close()