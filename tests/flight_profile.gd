extends "res://tests/test_runner.gd"
## Dev tool: CPU cost of a real flight: the full Flight stack (HUD, camera, replay, audio) in real time,
## using Godot's own frame timers. RC_ONE=1 limits it to one aircraft; RC_OFF=hud,cam,... disables subsystems.
## RC_SUITE=res://tests/flight_profile.gd godot --headless --path . -- --test
## Container CPU numbers, not phone numbers: compare aircraft, sections and before/after with each other.

const IDS := ["skylark", "viper90", "belle51", "cargo130", "skyliner"]
var _stack_ids: Array = ["skylark"] if OS.get_environment("RC_ONE") == "1" else IDS
const TICKS := 480

func _run_all() -> void:
	for id in _stack_ids:
		await _profile_stack(id)

func _start_cruise(a: Aircraft, alt: float, v: float) -> void:
	a.place(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(0, alt, 0)), v)
	for e in a.engines:
		e.running = true
		if e.type in ["edf", "turbine"]:
			e.rpm_frac = 0.6
		else:
			e.omega = 600.0

## utime + stime of this process (all threads) in seconds, from /proc: steadier than wall-clock frame timers
func _cpu_seconds() -> float:
	var f := FileAccess.open("/proc/self/stat", FileAccess.READ)
	if f == null:
		return 0.0
	var line := f.get_line()
	var rest := line.substr(line.rfind(")") + 2).split(" ")
	return (float(rest[11]) + float(rest[12])) / 100.0   # fields 14 and 15 (1-based)

func _count(n: Node, out: Dictionary) -> void:
	out[n.get_class()] = int(out.get(n.get_class(), 0)) + 1
	for c in n.get_children():
		_count(c, out)

func _free_all(n: Node, klass: String, keep: Array) -> void:
	for c in n.get_children():
		_free_all(c, klass, keep)
	if n.get_class() == klass and not (n.name in keep):
		n.queue_free()

func _profile_stack(id: String) -> void:
	if ac and is_instance_valid(ac):
		ac.queue_free()
		ac = null
		await _frames(2)
	Engine.max_physics_steps_per_frame = 6
	var main := get_parent()
	main.field = field
	main.fx = fx
	var fl := Flight.new()
	holder.add_child(fl)
	main.flight = fl
	main.state = "flight"
	fl.start(id, "free", field, fx, main.cam, main.ui)
	await get_tree().process_frame
	_start_cruise(fl.aircraft, 80.0, 20.0)
	fl.set_throttle(0.6)
	# RC_OFF=hud,cam,audio,replay,field,npcs,fx disables those subsystems, to see what each one costs
	var counts := {}
	_count(field, counts)
	print("FIELD nodes: ", counts)
	for key in OS.get_environment("RC_OFF").split(","):
		match key:
			"hud": fl.hud.process_mode = Node.PROCESS_MODE_DISABLED
			"cam": main.cam.process_mode = Node.PROCESS_MODE_DISABLED
			"audio": fl.audio.process_mode = Node.PROCESS_MODE_DISABLED
			"replay": fl.replay.process_mode = Node.PROCESS_MODE_DISABLED
			"field": field.process_mode = Node.PROCESS_MODE_DISABLED
			"npcs":
				for n in field.npcs:
					n.process_mode = Node.PROCESS_MODE_DISABLED
			"fx": fx.process_mode = Node.PROCESS_MODE_DISABLED
			"nostatic": _free_all(field, "StaticBody3D", ["TerrainBody"])
			"noareas": _free_all(field, "Area3D", [])
			"noparked":
				for a in field.parked:
					a.queue_free()
	for i in 120:
		await get_tree().process_frame
	var n := 600
	var sp := 0.0
	var sph := 0.0
	var worst := 0.0
	var ticks0 := Engine.get_physics_frames()
	var t0 := Time.get_ticks_usec()
	var cpu0 := _cpu_seconds()
	for i in n:
		await get_tree().process_frame
		var tp := Performance.get_monitor(Performance.TIME_PROCESS)
		var th := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		sp += tp
		sph += th
		worst = maxf(worst, tp + th)
	var wall := float(Time.get_ticks_usec() - t0) / 1e6
	var cpu_ms := (_cpu_seconds() - cpu0) / n * 1000.0
	var ticks := maxi(Engine.get_physics_frames() - ticks0, 1)
	print("STACK %-9s process=%.2f ms physics=%.2f ms per frame; physics ticks/s=%.0f (%.0f us per tick); worst frame %.2f ms; fps=%.0f; CPU %.2f ms/frame (all threads)" % [
		id, sp / n * 1000.0, sph / n * 1000.0, ticks / wall, sph * 1e6 / ticks, worst * 1000.0, n / wall, cpu_ms])
	fl.stop()
	main.flight = null
	main.state = "test"
	await _frames(3)

