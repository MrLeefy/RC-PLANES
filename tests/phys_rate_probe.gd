extends "res://tests/test_runner.gd"
## Dev tool: does the flight model give the same answers at lower physics tick rates?
## For each rate it flies the same roll and pitch steps and prints steady rates and a stability flag.
## RC_SUITE=res://tests/phys_rate_probe.gd godot --headless --fixed-fps 120 --path . -- --test
## (--fixed-fps stays 120: a 60 Hz sim then ticks every second frame, which is what a phone would do.)

const RATES := [120, 90, 60, 45]
const IDS := ["skylark", "vortex540", "macharrow", "viper90", "cargo130", "belle51"]
const GROUND_IDS := ["skylark", "tundra_cub", "belle51", "viper90"]

func _run_all() -> void:
	for id in IDS:
		var line := "%-10s" % id
		for hz in RATES:
			Engine.physics_ticks_per_second = hz
			var r: Dictionary = await _step_response(id, hz)
			line += " | %3d Hz: roll %6.1f deg/s  pitch %5.1f deg/s  v %4.1f%s" % [hz, r["p"], r["q"], r["v"], "  UNSTABLE" if r["bad"] else ""]
		print("RATE ", line)
	for id in GROUND_IDS:
		var gline := "%-10s" % id
		for hz in RATES:
			Engine.physics_ticks_per_second = hz
			var g: Dictionary = await _ground_cases(id, hz)
			gline += " | %3d Hz: rest dmg %.2f v %.3f  touchdown dmg %.2f bent %.2f  takeoff %5.1f m @ %4.1f m/s%s" % [hz, g["rest_dmg"], g["rest_v"], g["td_dmg"], g["td_bent"], g["to_dist"], g["to_v"], "  CRASH" if g["bad"] else ""]
		print("GROUND ", gline)
	Engine.physics_ticks_per_second = 120

func _fresh(id: String) -> void:
	if ac and is_instance_valid(ac):
		ac.queue_free()
		await _frames(2)
	fx.clear_chips()
	ac = Aircraft.new()
	ac.setup(AircraftDB.by_id(id), Settings.aircraft_cfg(id), 0, false)
	ac.assist = "expert"
	holder.add_child(ac)
	await _frames(2)

func _ground_cases(id: String, hz: int) -> Dictionary:
	var out := {"rest_dmg": 0.0, "rest_v": 0.0, "td_dmg": 0.0, "td_bent": 0.0, "to_dist": 0.0, "to_v": 0.0, "bad": false}
	# rest on the gear
	await _fresh(id)
	if String(ac.def["gear"]["type"]) == "taildragger":
		_ground_place(Vector3(-40, 0, 0), -PI * 0.5, 0.0, 0.18)
	else:
		_ground_place(Vector3(-40, 0, 0), -PI * 0.5)
	ac.brake = 1.0
	await _wait(2.0, hz, func(): pass)
	out["rest_dmg"] = _max_dmg()
	out["rest_v"] = ac.linear_velocity.length()
	# ordinary touchdown
	await _fresh(id)
	ac.place(Transform3D(Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3.RIGHT, deg_to_rad(4.0)), Vector3(-30, 0.5, 0)), 11.0)
	ac.linear_velocity += Vector3(0, -1.3, 0)
	await _wait(3.0, hz, func(): pass)
	out["td_dmg"] = _max_dmg()
	var bent := 0.0
	for w in ac.wheels:
		bent = maxf(bent, float(w["bent"]))
	out["td_bent"] = bent
	# take-off roll with a simple pilot
	await _fresh(id)
	if String(ac.def["gear"]["type"]) == "taildragger":
		_ground_place(Vector3(-70, 0, 0), -PI * 0.5, 0.0, 0.18)
	else:
		_ground_place(Vector3(-70, 0, 0), -PI * 0.5)
	for e in ac.engines:
		e.running = true
		if e.type in ["edf", "turbine"]:
			e.rpm_frac = 0.4
		else:
			e.omega = 300.0
	var x0 := ac.global_position.x
	var vr := 0.85 * ac.trim_speed()
	var air_t := 0.0
	for i in int(12.0 * hz):
		ac.set_inputs(0.0, 0.3 if ac.airspeed > vr else 0.0, 0.0, 1.0)
		await get_tree().physics_frame
		air_t = air_t + 1.0 / hz if not ac.on_ground else 0.0
		if air_t > 0.4:
			break
	out["to_dist"] = ac.global_position.x - x0
	out["to_v"] = ac.airspeed
	out["bad"] = ac.crashed_flag
	return out

func _wait(seconds: float, hz: int, fn: Callable) -> void:
	for i in int(seconds * hz):
		fn.call()
		await get_tree().physics_frame

func _step_response(id: String, hz: int) -> Dictionary:
	if ac and is_instance_valid(ac):
		ac.queue_free()
		await _frames(2)
	fx.clear_chips()
	ac = Aircraft.new()
	ac.setup(AircraftDB.by_id(id), Settings.aircraft_cfg(id), 0, false)
	ac.assist = "expert"
	holder.add_child(ac)
	await _frames(2)
	ac.place(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(0, 300, 0)), 24.0)
	for e in ac.engines:
		e.running = true
		if e.type in ["edf", "turbine"]:
			e.rpm_frac = 0.7
		else:
			e.omega = 700.0
	var out := {"p": 0.0, "q": 0.0, "v": 0.0, "bad": false}
	await _wait(1.0, hz, func(): ac.set_inputs(0.0, 0.0, 0.0, 0.6))
	await _wait(0.8, hz, func():
		ac.set_inputs(1.0, 0.0, 0.0, 0.6)
		var w: Vector3 = ac.global_transform.basis.transposed() * ac.angular_velocity
		out["p"] = absf(w.z) * 57.2958)
	await _wait(1.0, hz, func(): ac.set_inputs(0.0, 0.0, 0.0, 0.6))
	await _wait(0.5, hz, func():
		ac.set_inputs(0.0, 0.5, 0.0, 0.6)
		var w2: Vector3 = ac.global_transform.basis.transposed() * ac.angular_velocity
		out["q"] = absf(w2.x) * 57.2958)
	out["v"] = ac.linear_velocity.length()
	out["bad"] = not is_finite(ac.global_position.x) or ac.linear_velocity.length() > 150.0 or ac.crashed_flag
	return out
