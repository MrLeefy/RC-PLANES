class_name Flight
extends Node3D
## Flight session controller: inputs -> aircraft, camera, HUD, modes,
## crash aftermath -> kill cam -> repair loop, instant replay, rewind, pause.

signal exit_to_hangar
signal open_settings

enum S { FLYING, AFTERMATH, KILLCAM, KILLCAM_END, REPLAY, PAUSED }

var state := S.FLYING
var aircraft: Aircraft
var audio: EngineAudio
var cam: CameraRig
var hud: HUD
var kill: KillcamUI
var pause_ui: Control
var replay := Replay.new()
var tx := Transmitter.new()
var modes: Modes
var field: Field
var fx: Fx
var ui_layer: CanvasLayer
var sim_t := 0.0
var snapshots: Array = []
var snap_t := 0.0
var crash_info: Dictionary = {}
var crash_t := 0.0
var aftermath_t := 0.0
var keep_watching := false
var instant_snapshot: Dictionary = {}
var flight_cam_mode := "pilot"
var replay_views := ["cinematic", "chase", "wreck", "orbit", "pilot"]
var replay_view := "cinematic"
var gp_throttle := 0.0
var _throttle_hold := 0.0
var _crash_frame_start := 0
var parts_lost: Array = []
var crash_summary := ""
var _resume_state := S.FLYING

func start(id: String, mode_id: String, f: Field, effects: Fx, camera: CameraRig, layer: CanvasLayer) -> void:
	field = f
	fx = effects
	cam = camera
	ui_layer = layer
	Game.flight = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(replay)
	var def := AircraftDB.by_id(id)
	aircraft = Aircraft.new()
	aircraft.setup(def, Settings.aircraft_cfg(id), 2, false)
	aircraft.assist = String(Settings.g("gameplay", "assist", "sport"))
	aircraft.damage_mode = String(Settings.g("gameplay", "damage", "physical"))
	add_child(aircraft)
	aircraft.process_mode = Node.PROCESS_MODE_PAUSABLE
	audio = EngineAudio.new()
	aircraft.visual_root.add_child(audio)
	audio.setup(aircraft)
	aircraft.crashed.connect(_on_crash)
	aircraft.component_broken.connect(_on_broken)
	aircraft.touchdown.connect(func(info): modes.on_touchdown(info))
	aircraft.message.connect(func(t): show_toast(t))
	replay.bind(aircraft, fx, field.npcs)
	Sfx.world_sound.connect(replay.record_sound)
	tx.set_profile(Settings.tx_profile_for(id))
	cam.target = aircraft
	cam.override_target = false
	cam.pilot_pos = field.pilot_pos
	cam.auto_zoom = bool(Settings.g("gameplay", "auto_zoom", true))
	flight_cam_mode = String(Settings.g("gameplay", "camera", "pilot"))
	if not flight_cam_mode in CameraRig.MODES:
		flight_cam_mode = "pilot"
	hud = HUD.new()
	ui_layer.add_child(hud)
	hud.bind(aircraft, cam)
	hud.action.connect(_on_hud)
	hud.orbit.connect(func(relative): cam.orbit_drag(relative))
	hud.zoom.connect(func(factor): cam.orbit_zoom(factor))
	kill = KillcamUI.new()
	ui_layer.add_child(kill)
	kill.action.connect(_on_kill)
	kill.orbit.connect(func(relative): cam.orbit_drag(relative))
	kill.zoom.connect(func(factor): cam.orbit_zoom(factor))
	modes = Modes.new(self)
	modes.setup(mode_id)
	cam.set_mode(flight_cam_mode)
	cam.snap()
	Sfx.start_ambience()
	state = S.FLYING
	Diag.log_event("flight start %s %s" % [id, mode_id])

func stop() -> void:
	get_tree().paused = false
	Sfx.replay_transport_active = false
	Sfx.replay_transport_rate = 0.0
	replay.stop()
	if modes:
		modes.cleanup()
	if hud:
		hud.queue_free()
	if kill:
		kill.queue_free()
	if pause_ui:
		pause_ui.queue_free()
	Game.flight = null
	queue_free()

func show_toast(t: String) -> void:
	if hud and t != "":
		hud.show_toast(t)

func set_throttle(t: float) -> void:
	if hud:
		hud.sticks.set_throttle(t)
	gp_throttle = t

# ================================================================ loop
func _physics_process(delta: float) -> void:
	if get_tree().paused: return
	if state == S.FLYING or state == S.AFTERMATH:
		sim_t += delta
		Game.sim_time = sim_t
		replay.record(sim_t)
		if state == S.FLYING:
			snap_t += delta
			if snap_t >= 0.1:
				snap_t = 0.0
				snapshots.append([sim_t, _capture_snapshot()])
				if snapshots.size() > 120:
					snapshots.pop_front()
			modes.physics_update(delta)
	if state != S.PAUSED and state != S.KILLCAM and state != S.KILLCAM_END and state != S.REPLAY:
		Game.wind.step(delta)

func _process(delta: float) -> void:
	Sfx.replay_transport_active = replay.session_active
	Sfx.replay_transport_rate = replay.current_rate() if replay.playing and not replay.paused else 0.0
	if Game.wind:
		Game.wind.push_shader_globals()
	match state:
		S.FLYING:
			_read_inputs(delta)
			hud.info.text = modes.info_text()
			modes.update_ghost()
			_diag_state()
		S.AFTERMATH:
			aircraft.set_inputs(0, 0, 0, 0)
			aftermath_t -= delta
			cam.replay_focus = aircraft.vis_xf * aircraft.com_local
			if Engine.get_process_frames() == _crash_frame_start + 1:
				Diag.mark_crash_frame(delta * 1000.0)
			if aftermath_t <= 0.0 and not keep_watching:
				_start_killcam()
		S.KILLCAM, S.REPLAY:
			_update_replay_cam()
			kill.set_progress(replay.progress())
		S.KILLCAM_END:
			_update_replay_cam()
	if state in [S.KILLCAM, S.REPLAY, S.KILLCAM_END]:
		kill.set_timing(replay.play_t, replay.t0, replay.t1, replay.slow_center)
		kill.set_view_name(cam.mode)

func _read_inputs(delta: float) -> void:
	var v := hud.sticks.values()
	var roll := float(v["roll"])
	var pitch := float(v["pitch"])
	var yaw := float(v["yaw"])
	var thr := float(v["throttle"])
	# gamepad (optional): left stick rudder/throttle-rate, right stick aileron/elevator
	var pads := Input.get_connected_joypads()
	gp_throttle = thr
	if pads.size() > 0 and not hud.sticks.has_active_touches():
		var j: int = pads[0]
		var dz := 0.12
		var lx := Input.get_joy_axis(j, JOY_AXIS_LEFT_X)
		var ly := Input.get_joy_axis(j, JOY_AXIS_LEFT_Y)
		var rx := Input.get_joy_axis(j, JOY_AXIS_RIGHT_X)
		var ry := Input.get_joy_axis(j, JOY_AXIS_RIGHT_Y)
		var rt := Input.get_joy_axis(j, JOY_AXIS_TRIGGER_RIGHT)
		var lt := Input.get_joy_axis(j, JOY_AXIS_TRIGGER_LEFT)
		if maxf(maxf(absf(lx), absf(ly)), maxf(absf(rx), absf(ry))) > dz or rt > dz or lt > dz:
			roll = _dz(rx, dz)
			pitch = _dz(ry, dz)
			yaw = _dz(lx, dz)
			gp_throttle = clampf(gp_throttle - _dz(ly, dz) * delta * 0.7 + (rt - lt) * delta * 0.8, 0.0, 1.0)
			hud.sticks.set_throttle(gp_throttle)
			thr = gp_throttle
	var shaped := tx.process(roll, pitch, yaw, delta)
	aircraft.set_inputs(shaped.x, shaped.y, shaped.z, thr)
	aircraft.brake = 1.0 if (thr < 0.03 and bool(Settings.g("controls", "throttle_brake", true)) and aircraft.on_ground) else 0.0
	if Engine.get_process_frames() % 6 == 0:
		Diag.log_input([snappedf(roll, 0.01), snappedf(pitch, 0.01), snappedf(yaw, 0.01), snappedf(thr, 0.01)])

func _dz(x: float, dz: float) -> float:
	if absf(x) < dz:
		return 0.0
	return signf(x) * (absf(x) - dz) / (1.0 - dz)

func _diag_state() -> void:
	if Engine.get_process_frames() % 30 != 0:
		return
	Diag.physics_state = {"aircraft": aircraft.def["id"], "pos": str(aircraft.global_position), "vel": str(aircraft.linear_velocity),
		"airspeed": aircraft.airspeed, "aoa": rad_to_deg(aircraft.aoa), "agl": aircraft.agl, "mass": aircraft.mass,
		"cg": str(aircraft.com_local), "assist": aircraft.assist, "damage": aircraft.damage_mode, "sim_t": sim_t}

# ================================================================ HUD actions
func _on_hud(a: String) -> void:
	if state != S.FLYING:
		return
	match a:
		"pause": pause_game()
		"camera":
			flight_cam_mode = cam.next_mode(CameraRig.MODES)
			show_toast("Camera: " + flight_cam_mode.capitalize())
		"engine":
			aircraft.engine_toggle()
			if not aircraft.is_electric():
				Sfx.play3d("starter", aircraft.global_position, 0.8)
		"flaps":
			var f := aircraft.cycle_flaps()
			show_toast("Flaps " + ["up", "half", "full"][int(round(f * 2.0))])
		"gear":
			aircraft.toggle_gear()
			show_toast("Gear " + ("down" if aircraft.gear_down else "up"))
		"reset":
			repair_and_fly()
		"replay":
			start_instant_replay()
		"rewind":
			rewind(5.0)

func pause_game() -> void:
	if state not in [S.FLYING, S.AFTERMATH]: return
	_resume_state = state
	state = S.PAUSED
	hud.release_controls()
	get_tree().paused = true
	pause_ui = PauseMenu.new()
	pause_ui.action.connect(_on_pause)
	ui_layer.add_child(pause_ui)

func resume_game() -> void:
	if pause_ui:
		pause_ui.queue_free()
		pause_ui = null
	get_tree().paused = false
	state = _resume_state
	# re-read settings that may have changed
	hud.sticks.configure()
	hud.call("_layout")
	tx.set_profile(Settings.tx_profile_for(String(aircraft.def["id"])))
	aircraft.assist = String(Settings.g("gameplay", "assist", "sport"))
	aircraft.damage_mode = String(Settings.g("gameplay", "damage", "physical"))
	cam.auto_zoom = bool(Settings.g("gameplay", "auto_zoom", true))
	modes.reconcile_setup()

func _on_pause(a: String) -> void:
	match a:
		"resume": resume_game()
		"restart":
			resume_game()
			repair_and_fly()
		"settings": open_settings.emit()
		"hangar":
			get_tree().paused = false
			exit_to_hangar.emit()
		"diag":
			var p := Diag.export_report({"aircraft": aircraft.def["id"], "health": aircraft.health_summary(), "impacts": aircraft.impact_log})
			var message := "Saved in app storage: " + String(p.get("path", "")).get_file() if p.get("ok", false) else "Save failed: " + String(p.get("error", "unknown error"))
			if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
				DisplayServer.clipboard_set(String(p["text"]))
				message += "  • Report copied for sharing"
			show_toast(message)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if state in [S.FLYING, S.AFTERMATH]:
			pause_game()
		elif state in [S.KILLCAM, S.REPLAY]:
			replay.paused = true
			kill.set_playing(false)
			hud.release_controls()

func handle_back() -> void:
	match state:
		S.FLYING: pause_game()
		S.PAUSED: resume_game()
		S.AFTERMATH, S.KILLCAM: _on_kill("skip", 0.0)
		S.REPLAY: _on_kill("resume", 0.0)
		S.KILLCAM_END: _on_kill("repair", 0.0)

# ================================================================ crash / kill cam
func _on_broken(id: String, info: Dictionary) -> void:
	parts_lost.append(id)
	if state == S.FLYING and not info.get("secondary", false):
		show_toast(hud._pretty(id) + " broke off!")

func _on_crash(info: Dictionary) -> void:
	if state != S.FLYING:
		return
	crash_info = info.duplicate(true)
	crash_t = sim_t
	replay.pin_crash(crash_t)
	_crash_frame_start = Engine.get_process_frames()
	hud.release_controls()
	hud.visible = false
	var sev := float(info.get("sev", 0.0))
	crash_summary = _cause_text(String(info.get("cause", ""))).capitalize()
	var contact_speed := float(info.get("contact_speed_mps", 0.0))
	if contact_speed > 0.0:
		crash_summary += " • recorded contact %.0f km/h" % (contact_speed * 3.6)
	kill.summary = crash_summary
	Diag.log_event("crash sev=%.1f cause=%s" % [sev, info.get("cause", "")])
	if not bool(Settings.g("gameplay", "killcam", true)):
		state = S.KILLCAM_END
		get_tree().paused = true
		_end_panel()
		return
	state = S.AFTERMATH
	aftermath_t = float(Settings.g("gameplay", "aftermath", 4.0))
	keep_watching = false
	kill.set_phase("live")
	replay_view = "cinematic"
	cam.override_target = false
	cam.set_mode("cinematic")
	kill.set_view_name("cinematic")

func _cause_text(c: String) -> String:
	match c:
		"tail": return "tail section torn off"
		"wings": return "lost both wings"
		"breakup": return "airframe broke up"
		"cartwheel": return "cartwheeled in"
		"tree": return "hit a tree"
		"structure": return "hit a building"
		"vehicle": return "hit a car"
		"person": return "hit a spectator"
		"net", "fence": return "caught the fence"
		"ground": return "hit the ground"
	return c

func _start_killcam() -> void:
	state = S.KILLCAM
	get_tree().paused = true
	replay.speed = 1.0
	replay.slow_factor = float(Settings.g("gameplay", "slowmo", 0.3))
	kill.reset_speed()
	replay.start(crash_t - 6.0, sim_t, crash_t)
	if not replay.session_active:
		state = S.KILLCAM_END
		_end_panel()
		show_toast("Not enough recorded frames for this impact")
		return
	if not replay.ended.is_connected(_on_replay_end):
		replay.ended.connect(_on_replay_end)
	kill.set_phase("replay")
	kill.set_playing(true)
	cam.override_target = true
	cam.set_mode(replay_view)
	kill.set_view_name(replay_view)

func _on_replay_end() -> void:
	if state == S.KILLCAM:
		state = S.KILLCAM_END
		_end_panel()
	elif state == S.REPLAY:
		kill.set_playing(false)

func _end_panel() -> void:
	var lost := []
	for c in aircraft.comps:
		if c["detached"]:
			lost.append(hud._pretty(String(c["id"])))
	var txt := crash_summary
	if not lost.is_empty():
		txt += "\nParts lost: " + ", ".join(lost.slice(0, 6)) + ("..." if lost.size() > 6 else "")
	kill.summary = txt
	kill.set_phase("end")
	kill.set_playing(false)
	cam.set_mode("orbit")
	kill.set_view_name("orbit")

func _update_replay_cam() -> void:
	if replay.session_active:
		cam.target_xf = aircraft.vis_xf
		cam.target_vel = replay.velocity_at(replay.play_t)
	else:
		cam.target_xf = aircraft.vis_xf
		cam.target_vel = Vector3.ZERO
	cam.override_target = true
	cam.shot_clock = replay.play_t
	var anchor_t := maxf(replay.t0, floor(replay.play_t / CameraRig.SHOT_SECONDS) * CameraRig.SHOT_SECONDS)
	cam.shot_origin = replay.focus_at(anchor_t)
	cam.shot_velocity = replay.velocity_at(anchor_t)
	cam.replay_focus = replay.focus_at(replay.play_t) if replay.session_active else aircraft.vis_xf * aircraft.com_local
	cam.replay_aircraft_focus = cam.replay_focus
	if replay_view == "part" or cam.mode == "part":
		# follow the largest detached part
		var best_m := 0.0
		for i in aircraft.comps.size():
			var c: Dictionary = aircraft.comps[i]
			var owner := aircraft.replay_owners[i] if replay.session_active and i < aircraft.replay_owners.size() else int(c["debris"])
			if owner == i and float(c["mass"]) > best_m:
				best_m = float(c["mass"])
				cam.replay_focus = (c["visual"] as Node3D).global_transform * (c["center"] as Vector3)

func _on_kill(a: String, v: float) -> void:
	match a:
		"keep":
			keep_watching = true
			aftermath_t = 0.0
			kill.sub.text = "Watching live physics - press SKIP for the kill cam"
		"skip":
			if state == S.AFTERMATH:
				_start_killcam()
			elif state == S.KILLCAM:
				replay.finish()
				state = S.KILLCAM_END
				_end_panel()
		"playpause":
			if state in [S.KILLCAM, S.REPLAY, S.KILLCAM_END]:
				if not replay.playing or replay.finished:
					if state == S.KILLCAM_END:
						state = S.KILLCAM
						kill.set_phase("replay")
					replay.start(replay.t0, replay.t1, replay.slow_center)
					kill.set_playing(true)
				else:
					replay.paused = not replay.paused
					kill.set_playing(not replay.paused)
		"seek":
			if replay.session_active:
				replay.seek(v)
				kill.set_playing(false)
				if state == S.KILLCAM_END:
					state = S.KILLCAM
					kill.set_phase("replay")
					kill.set_playing(false)
				_update_replay_cam()
		"speed":
			replay.speed = v
		"view":
			var views := replay_views.duplicate()
			if state == S.KILLCAM_END:
				views = ["orbit", "cinematic", "pilot", "part"]
			var i := views.find(cam.mode)
			var nv: String = views[(i + 1) % views.size()]
			replay_view = nv
			cam.set_mode(nv)
			kill.set_view_name(nv)
		"again":
			state = S.KILLCAM
			kill.set_phase("replay")
			kill.reset_speed()
			replay.speed = 1.0
			replay.start(crash_t - 6.0, replay.newest_t(), crash_t)
			cam.set_mode(replay_view if replay_view != "orbit" else "cinematic")
			kill.set_playing(true)
		"repair":
			repair_and_fly()
		"rewind":
			rewind_to(crash_t - 5.0)
		"hangar":
			get_tree().paused = false
			exit_to_hangar.emit()
		"resume":
			_end_instant_replay()

func repair_and_fly() -> void:
	replay.stop()
	get_tree().paused = false
	aircraft.replay_driven = false
	aircraft.repair_all()
	fx.clear_chips()
	field.reset_npcs()
	modes.respawn()
	replay.clear()
	snapshots.clear()
	parts_lost.clear()
	kill.set_phase("")
	hud.visible = true
	hud.release_controls()
	cam.override_target = false
	cam.set_mode(flight_cam_mode)
	cam.snap()
	tx.reset()
	state = S.FLYING

# ================================================================ instant replay & rewind
func start_instant_replay() -> void:
	if replay.count < 30:
		show_toast("Nothing to replay yet")
		return
	state = S.REPLAY
	hud.release_controls()
	instant_snapshot = _capture_snapshot()
	get_tree().paused = true
	hud.visible = false
	replay.speed = 1.0
	kill.reset_speed()
	replay.start(maxf(sim_t - 12.0, replay.oldest_t()), sim_t, -1.0)
	if not replay.ended.is_connected(_on_replay_end):
		replay.ended.connect(_on_replay_end)
	kill.set_phase("instant")
	replay_view = "chase"
	cam.set_mode("chase")
	kill.set_view_name("chase")

func _end_instant_replay() -> void:
	replay.stop()
	aircraft.replay_driven = false
	_restore_snapshot(instant_snapshot)
	get_tree().paused = false
	kill.set_phase("")
	hud.visible = true
	cam.override_target = false
	cam.set_mode(flight_cam_mode)
	cam.snap()
	state = S.FLYING

func rewind(sec: float) -> void:
	rewind_to(sim_t - sec)

func rewind_to(t: float) -> void:
	if snapshots.is_empty():
		show_toast("Nothing to rewind to")
		return
	var pick: Array = snapshots[0]
	for s in snapshots:
		if float(s[0]) <= t:
			pick = s
	replay.stop()
	get_tree().paused = false
	aircraft.replay_driven = false
	_restore_snapshot(pick[1])
	fx.clear_chips()
	field.reset_npcs()
	sim_t = float(pick[0])
	Game.sim_time = sim_t
	modes.invalidate_for_rewind()
	replay.truncate_after(sim_t)
	while snapshots.size() > 0 and float(snapshots[snapshots.size() - 1][0]) > sim_t:
		snapshots.pop_back()
	# Preserve the historical ratcheted throttle; release only pointer ownership.
	hud.release_controls()
	set_throttle(aircraft.in_throttle)
	kill.set_phase("")
	hud.visible = true
	cam.override_target = false
	cam.set_mode(flight_cam_mode)
	state = S.FLYING
	show_toast("Rewound — practice attempt; objectives and spectators reset")

func _capture_snapshot() -> Dictionary:
	return {"version": 2, "aircraft": aircraft.snapshot(), "transmitter": tx.snapshot(), "throttle": hud.sticks.throttle}

func _restore_snapshot(saved: Dictionary) -> void:
	if saved.has("aircraft"):
		aircraft.restore(saved["aircraft"])
		tx.restore(saved["transmitter"])
		set_throttle(float(saved["throttle"]))
	else:
		aircraft.restore(saved)
		set_throttle(aircraft.in_throttle)
	hud.release_controls()