class_name Modes
extends RefCounted
## Game modes: spawn conditions + objectives + unobtrusive feedback.

const LIST := [
	["free", "Free Flight"], ["landing", "Landing Practice"], ["crosswind", "Crosswind Landing"],
	["engine_out", "Engine-Out Landing"], ["touchgo", "Touch-and-Go"], ["aerobatic", "Aerobatic Practice"],
	["gates", "Gate Course"], ["timetrial", "Time Trial + Ghost"],
]

var fl: Node   # Flight
var id := "free"
var ac: Aircraft
# landing analysis
var land_state := 0   # 0 idle, 1 touched, 2 rolling out
var td_vs := 0.0
var td_pos := Vector3.ZERO
var td_speed := 0.0
var bounces := 0
var last_td_t := 0.0
var airborne_since := 0.0
var landed_reported := false
var touch_and_goes := 0
var tg_touched := false
# aerobatics
var roll_acc := 0.0
var pitch_acc := 0.0
var yaw_acc := 0.0
var inverted_t := 0.0
var knife_t := 0.0
var tricks: Array = []
var score := 0
# gates / time trial
var gate_idx := 0
var gate_nodes: Array = []
var run_t := 0.0
var running := false
var best := -1.0
var ghost_track: Array = []
var ghost_best: Array = []
var ghost_node: Node3D = null
var ghost_rec_t := 0.0
var practice := false
var practice_reason := ""
var record_key := ""
const COURSE_REVISION := 2

func _init(flight: Node) -> void:
	fl = flight

func title() -> String:
	for m in LIST:
		if m[0] == id:
			return m[1]
	return "Free Flight"

func setup(mode_id: String) -> void:
	id = mode_id
	ac = fl.aircraft
	var wind_preset := String(Settings.g("environment", "wind", "light"))
	var wind_dir := String(Settings.g("environment", "wind_dir", "headwind"))
	if id == "crosswind":
		wind_preset = "gusty" if wind_preset in ["calm", "light"] else wind_preset
		wind_dir = "crosswind_left" if Game.rng.randf() < 0.5 else "crosswind_right"
	Game.wind.configure(wind_preset, wind_dir, Vector3(1, 0, 0))
	if id in ["gates", "timetrial"]:
		_make_course()
	respawn()

func runway_dir() -> Vector3:
	# take off / land into the wind
	var w: Vector3 = Game.wind.base_dir
	if Game.wind.base_speed > 0.5 and w.x > 0.3:
		return Vector3(-1, 0, 0)
	return Vector3(1, 0, 0)

func _ground_xf(pos: Vector3, heading: Vector3) -> Transform3D:
	var yaw := atan2(-heading.x, -heading.z)
	var b := Basis(Vector3.UP, yaw)
	var low := 0.0
	for w in ac.wheels:
		low = minf(low, (w["center"] as Vector3).y - float(w["r"]))
	if String(ac.def["gear"]["type"]) == "taildragger":
		var main: Dictionary = ac.wheels[0]
		var tail: Dictionary = ac.wheels[ac.wheels.size() - 1]
		var ang := atan2(((tail["center"] as Vector3).y - float(tail["r"])) - ((main["center"] as Vector3).y - float(main["r"])),
			(tail["center"] as Vector3).z - (main["center"] as Vector3).z)
		b = b * Basis(Vector3.RIGHT, ang)
	var tmp := Transform3D(b, Vector3.ZERO)
	var lowy := 0.0
	for w in ac.wheels:
		lowy = minf(lowy, (tmp * ((w["center"] as Vector3) - Vector3(0, float(w["r"]), 0))).y)
	var gy: float = Game.field.ground_y(pos) if Game.field else 0.0
	return Transform3D(b, Vector3(pos.x, gy - lowy + 0.01, pos.z))

func _air_xf(pos: Vector3, heading: Vector3, pitch := 0.0) -> Transform3D:
	var yaw := atan2(-heading.x, -heading.z)
	return Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), pos)

func _vs_est() -> float:
	return sqrt(2.0 * ac.mass * 9.81 / (1.225 * ac.ref_area * 1.25))

func respawn() -> void:
	ac = fl.aircraft
	practice = false
	practice_reason = ""
	record_key = _setup_key()
	if id in ["gates", "timetrial"]: _load_ghost()
	reset_objectives()
	var rd := runway_dir()
	land_state = 0
	landed_reported = false
	bounces = 0
	touch_and_goes = 0
	tricks.clear()
	score = 0
	gate_idx = 0
	running = false
	run_t = 0.0
	ghost_track.clear()
	ac.flap_cmd = 0.0
	ac.flap_pos = 0.0
	ac.gear_down = true
	ac.gear_pos = 1.0
	var thr := 0.0
	match id:
		"landing", "crosswind":
			var vapp := _vs_est() * 1.45
			var start := Vector3(-rd.x * 150.0, 16.0, 0.0)
			ac.place(_air_xf(start, rd, deg_to_rad(-2.0)), vapp)
			ac.flap_cmd = 0.5 if ac.has_flaps() else 0.0
			ac.flap_pos = ac.flap_cmd
			thr = 0.3
			_force_engines(true)
			fl.show_toast("Land on the runway. Rewind (-5 s) to retry the approach.")
		"engine_out":
			var start2 := Vector3(-rd.x * 60.0, 70.0, -120.0)
			ac.place(_air_xf(start2, -rd), _vs_est() * 1.7)
			_force_engines(false)
			fl.show_toast("Engine out! Glide it back and land.")
		"gates", "timetrial":
			ac.place(_ground_xf(Vector3(-rd.x * 55.0, 0, 0), rd))
			_force_engines(ac.is_electric())
			fl.show_toast("Fly through the gates in order" + (" - timer starts at gate 1" if id == "timetrial" else ""))
		_:
			ac.place(_ground_xf(Vector3(-rd.x * 55.0, 0, 0), rd))
			_force_engines(ac.is_electric())
			if not ac.is_electric():
				fl.show_toast("Tap ENGINE to start, then taxi and take off")
			else:
				fl.show_toast("Motor armed - throttle up to take off")
	fl.set_throttle(thr)
	if gate_nodes.size() > 0:
		_highlight_gate()

func _force_engines(on: bool) -> void:
	for e in ac.engines:
		var p := e as Propulsion
		p.starting = 0.0
		if on:
			p.running = true
			if p.is_prop():
				p.omega = 500.0
			else:
				p.rpm_frac = 0.4 if p.type == "turbine" else 0.2
		else:
			p.running = false
			p.omega = 0.0
			p.rpm_frac = 0.0

# ------------------------------------------------------------------ per physics tick
func physics_update(dt: float) -> void:
	if ac == null:
		return
	_landing_analysis(dt)
	if id == "aerobatic":
		_aerobatics(dt)
	if id in ["gates", "timetrial"]:
		_gates(dt)

func on_touchdown(info: Dictionary) -> void:
	if land_state == 0 or fl.sim_t - last_td_t > 4.0:
		land_state = 1
		td_vs = float(info["vs"])
		td_pos = info["pos"]
		td_speed = float(info["speed"])
		bounces = 0
		landed_reported = false
	elif fl.sim_t - last_td_t > 0.3:
		bounces += 1
	last_td_t = fl.sim_t
	if id == "touchgo":
		tg_touched = Game.surface_at(info["pos"]) == Game.SURF_ASPHALT or Game.surface_at(info["pos"]) == Game.SURF_GRASS

func _landing_analysis(dt: float) -> void:
	if ac.on_ground:
		airborne_since = 0.0
		if land_state == 1 and ac.ground_speed < 1.0 and not landed_reported and not ac.crashed_flag:
			landed_reported = true
			land_state = 0
			var rollout := Vector2(ac.global_position.x - td_pos.x, ac.global_position.z - td_pos.z).length()
			var on_rwy := absf(td_pos.x) <= 70.0 and absf(td_pos.z) <= 6.0
			var drift := absf(td_pos.z)
			var grade := "Butter!" if td_vs < 0.6 else ("Smooth" if td_vs < 1.2 else ("Firm" if td_vs < 2.2 else "Hard"))
			if bounces > 1:
				grade = "Bouncy"
			var txt := "%s landing\nTouchdown sink  %.2f m/s\nCentreline offset  %.1f m\n%s  x=%.0f m\nBounces  %d   Rollout  %.0f m" % [
				grade, td_vs, drift, "On runway" if on_rwy else "Off runway", td_pos.x, bounces, rollout]
			if Settings.g("gameplay", "landing_feedback", true):
				fl.hud.show_landing(txt)
			Diag.log_event("landing vs=%.2f drift=%.1f bounces=%d" % [td_vs, drift, bounces])
	else:
		airborne_since += dt
		if id == "touchgo" and tg_touched and airborne_since > 1.5:
			tg_touched = false
			touch_and_goes += 1
			fl.hud.show_trick("Touch-and-go #%d" % touch_and_goes)
		if airborne_since > 1.0 and land_state == 1:
			land_state = 0

func _aerobatics(dt: float) -> void:
	var B := ac.global_transform.basis
	var w_l := B.transposed() * ac.angular_velocity
	var p := -w_l.z
	var q := w_l.x
	var r := -w_l.y
	if ac.agl < 3.0 or ac.airspeed < 3.0:
		roll_acc = 0.0
		pitch_acc = 0.0
		yaw_acc = 0.0
		return
	roll_acc += p * dt
	pitch_acc += q * dt
	yaw_acc += r * dt
	if absf(roll_acc) > TAU * 0.95:
		_trick("Roll" if absf(pitch_acc) < 1.0 else "Barrel roll", 100)
		roll_acc = 0.0
		pitch_acc = 0.0
	if absf(pitch_acc) > TAU * 0.95:
		_trick("Loop" if pitch_acc > 0.0 else "Outside loop!", 150 if pitch_acc > 0.0 else 250)
		pitch_acc = 0.0
		roll_acc = 0.0
	var stalled := absf(ac.aoa) > deg_to_rad(18.0)
	if absf(yaw_acc) > TAU * 0.95 and stalled:
		_trick("Spin turn", 150)
		yaw_acc = 0.0
	elif absf(yaw_acc) > TAU * 1.2:
		yaw_acc = 0.0
	# decay accumulators slowly so partial manoeuvres don't add up forever
	roll_acc *= 1.0 - dt * 0.15
	pitch_acc *= 1.0 - dt * 0.15
	yaw_acc *= 1.0 - dt * 0.3
	if B.y.y < -0.85:
		inverted_t += dt
		if inverted_t > 3.0:
			_trick("Inverted pass", 120)
			inverted_t = -30.0
	elif inverted_t > 0.0:
		inverted_t = 0.0
	elif inverted_t < 0.0:
		inverted_t = minf(inverted_t + dt * 4.0, 0.0)
	if absf(B.x.y) > 0.9 and absf(ac.linear_velocity.y) < 2.0 and ac.airspeed > 8.0:
		knife_t += dt
		if knife_t > 2.0:
			_trick("Knife-edge", 200)
			knife_t = -30.0
	elif knife_t > 0.0:
		knife_t = 0.0
	elif knife_t < 0.0:
		knife_t = minf(knife_t + dt * 4.0, 0.0)

func _trick(name: String, pts: int) -> void:
	tricks.append(name)
	score += pts
	fl.hud.show_trick("%s  +%d" % [name, pts])
	Sfx.ui("beep", 0.4)

func _make_course() -> void:
	var pts := [
		[Vector3(-20, 8, -30), PI * 0.5], [Vector3(60, 12, -60), PI * 0.25], [Vector3(110, 15, -10), 0.0],
		[Vector3(70, 10, 5), -PI * 0.5], [Vector3(0, 6, 0), -PI * 0.5], [Vector3(-80, 14, -20), -PI * 0.25],
		[Vector3(-100, 18, -80), PI * 0.1], [Vector3(-30, 10, -70), PI * 0.5]]
	gate_nodes = Game.field.make_gates(pts)

func _highlight_gate() -> void:
	for i in gate_nodes.size():
		var g: Node3D = gate_nodes[i]
		var mi: MeshInstance3D = g.get_meta("mesh")
		var m := mi.mesh.surface_get_material(0) as StandardMaterial3D
		var mat := m.duplicate() as StandardMaterial3D
		if i == gate_idx:
			mat.emission = Color(0.1, 1.0, 0.3)
			mat.emission_energy_multiplier = 1.5
		elif i < gate_idx:
			mat.emission = Color(0.2, 0.2, 0.2)
			mat.emission_energy_multiplier = 0.2
		else:
			mat.emission = Color(1.0, 0.45, 0.1)
			mat.emission_energy_multiplier = 0.4
		mi.material_override = mat

func _gates(dt: float) -> void:
	if running:
		run_t += dt
		ghost_rec_t += dt
		if ghost_rec_t >= 0.05:
			ghost_rec_t = 0.0
			if not practice:
				if ghost_track.size() < GhostCodec.MAX_SAMPLES and run_t < GhostCodec.MAX_SECONDS:
					ghost_track.append([run_t, ac.global_transform])
				else:
					practice = true
					practice_reason = "recording limit"
					ghost_track.clear()
					fl.show_toast("Practice: ghost limit reached; flight continues")
	if gate_idx >= gate_nodes.size():
		return
	var g: Node3D = gate_nodes[gate_idx]
	var ar: Area3D = g.get_meta("area")
	if ar.overlaps_body(ac):
		gate_idx += 1
		Sfx.ui("beep", 0.6)
		if gate_idx == 1 and id == "timetrial":
			running = true
			run_t = 0.0
			ghost_track.clear()
			ghost_rec_t = 0.0
			if not practice: ghost_track.append([0.0, ac.global_transform])
			_start_ghost()
		if gate_idx >= gate_nodes.size():
			running = false
			var msg := "Course complete!"
			if id == "timetrial":
				msg = "Finish: %s" % _fmt(run_t)
				if not practice and (best < 0.0 or run_t < best):
					if _save_ghost(run_t):
						msg += "  NEW BEST"
					else:
						msg += "  (record not saved)"
				elif practice:
					msg += "  PRACTICE — no record"
			fl.hud.show_trick(msg)
		else:
			fl.hud.show_trick("Gate %d / %d" % [gate_idx, gate_nodes.size()])
		_highlight_gate()

func _fmt(t: float) -> String:
	return "%02d:%05.2f" % [int(t / 60.0), fmod(t, 60.0)]

func info_text() -> String:
	if practice: return "PRACTICE • " + practice_reason + " • repair to start a scored attempt"
	match id:
		"touchgo":
			return "Touch-and-goes: %d" % touch_and_goes
		"aerobatic":
			return "Score %d" % score
		"gates", "timetrial":
			var s := "Gate %d/%d" % [mini(gate_idx + 1, gate_nodes.size()), gate_nodes.size()]
			if id == "timetrial":
				s += "   %s" % _fmt(run_t)
				if best > 0.0:
					s += "   best %s" % _fmt(best)
			return s
	return ""

# ------------------------------------------------------------------ ghost (previous best run)
func _setup_key() -> String:
	var wind := Game.wind
	return JSON.stringify([COURSE_REVISION, id, ac.def["id"], ac.cfg, ac.assist, ac.damage_mode,
		fl.tx.profile, wind.base_speed, wind.base_dir, wind.gust_amp, wind.turb]).sha256_text().substr(0, 32)

func reconcile_setup() -> void:
	if record_key != _setup_key():
		practice = true
		practice_reason = "setup changed"
		ghost_track.clear()
		ghost_best.clear()
		if is_instance_valid(ghost_node): ghost_node.visible = false

func reset_objectives() -> void:
	land_state = 0
	landed_reported = false
	bounces = 0
	last_td_t = 0.0
	airborne_since = 0.0
	touch_and_goes = 0
	tg_touched = false
	roll_acc = 0.0
	pitch_acc = 0.0
	yaw_acc = 0.0
	inverted_t = 0.0
	knife_t = 0.0
	tricks.clear()
	score = 0
	gate_idx = 0
	running = false
	run_t = 0.0
	ghost_rec_t = 0.0
	ghost_track.clear()
	if is_instance_valid(ghost_node): ghost_node.visible = false
	if not gate_nodes.is_empty(): _highlight_gate()

func invalidate_for_rewind() -> void:
	reset_objectives()
	practice = true
	practice_reason = "rewind used"

func _ghost_path() -> String:
	return "user://ghost_v2_%s_%s.json" % [String(ac.def["id"]), record_key]

func _save_ghost(time: float) -> bool:
	if practice or record_key != _setup_key(): return false
	var data := GhostCodec.encode(ghost_track, record_key, time)
	var valid := GhostCodec.decode(data, record_key)
	if not valid.get("ok", false):
		Diag.log_event("Ghost rejected: " + String(valid.get("error", "")))
		return false
	var result := SafeStore.write_json(_ghost_path(), data)
	if not result.get("ok", false):
		Diag.log_event("Ghost save failed: " + String(result.get("error", "")))
		return false
	best = time
	ghost_best = ghost_track.duplicate(true)
	Settings.data["records"][record_key] = best
	Settings.save()
	return true

func _load_ghost() -> void:
	ghost_best.clear()
	best = -1.0
	for path in [_ghost_path(), _ghost_path() + ".bak"]:
		var file := SafeStore.read_json(path)
		if not file.get("ok", false): continue
		var decoded := GhostCodec.decode(file["data"], record_key)
		if decoded.get("ok", false):
			best = decoded["best"]
			ghost_best = decoded["track"]
			return
		Diag.log_event("Ignored invalid/incompatible ghost: " + String(decoded.get("error", "")))

func _start_ghost() -> void:
	if practice or ghost_best.is_empty() or id != "timetrial":
		return
	if ghost_node == null or not is_instance_valid(ghost_node):
		var b := AircraftBuilder.new()
		var r := b.build(ac.def, ac.cfg, 0)
		ghost_node = r["root"]
		_ghostify(ghost_node)
		fl.add_child(ghost_node)
	ghost_node.visible = true

func _ghostify(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			(c as MeshInstance3D).material_override = MatLib.ghost()
			(c as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if c is Label3D:
			(c as Label3D).visible = false
		_ghostify(c)

func update_ghost() -> void:
	if ghost_node == null or not is_instance_valid(ghost_node) or not running or ghost_best.is_empty():
		if ghost_node and is_instance_valid(ghost_node) and not running:
			ghost_node.visible = false
		return
	var t := run_t
	var i := GhostCodec.index_at(ghost_best, t)
	var a: Array = ghost_best[i]
	var b: Array = ghost_best[mini(i + 1, ghost_best.size() - 1)]
	var k := clampf((t - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1e-4), 0.0, 1.0)
	ghost_node.global_transform = (a[1] as Transform3D).interpolate_with(b[1], k)
	ghost_node.visible = t <= float(ghost_best[ghost_best.size() - 1][0])

func cleanup() -> void:
	if ghost_node and is_instance_valid(ghost_node):
		ghost_node.queue_free()
	for g in gate_nodes:
		if is_instance_valid(g):
			(g as Node).queue_free()
	gate_nodes.clear()