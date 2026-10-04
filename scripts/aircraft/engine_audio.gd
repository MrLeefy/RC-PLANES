class_name EngineAudio
extends Node3D
## Per-aircraft audio: engine tone + load/noise layers driven by simulated RPM and
## throttle, airframe wind, tyre roll and scraping. 3D players with Doppler, so a
## low pass sounds like a real flyby.

var ac: Aircraft
var layers: Array = []   # per engine: {tone, noise, type}
var wind: AudioStreamPlayer3D
var roll: AudioStreamPlayer3D
var scrape: AudioStreamPlayer3D
var servo: AudioStreamPlayer3D
var gear_motor: AudioStreamPlayer3D
var brake_squeal: AudioStreamPlayer3D
var started := false
var _prev_defl: Array = []
var _servo_act := 0.0
var _prev_gear := 1.0
var _was_running: Array = []
var _lopey_t := 0.0
var last_surface := -1
var _replay_was_active := false

func setup(aircraft: Aircraft) -> void:
	ac = aircraft
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not Sfx.ready_flag:
		return
	for ei in ac.engines.size():
		var e: Propulsion = ac.engines[ei]
		var t := e.type
		var tone := _player(Sfx.bank[t] if Sfx.bank.has(t) else Sfx.bank["electric"], "Engine", 10.0)
		var noise_name := "prop_swish"
		if t == "edf":
			noise_name = "edf_noise"
		elif t == "turbine":
			noise_name = "turbine_roar"
		var noise := _player(Sfx.bank[noise_name], "Engine", 12.0)
		tone.position = e.pos
		noise.position = e.pos + Vector3(0, 0, 0.2)
		layers.append({"tone": tone, "noise": noise, "type": t})
	wind = _player(Sfx.bank["wind"], "SFX", 5.0)
	roll = _player(Sfx.bank["roll_asphalt"], "SFX", 4.0)
	scrape = _player(Sfx.bank["scrape"], "SFX", 4.0)
	servo = _player(Sfx.bank["servo"], "SFX", 1.5)
	gear_motor = _player(Sfx.bank["retract_motor"], "SFX", 1.5)
	brake_squeal = _player(Sfx.bank["brake_squeal"], "SFX", 3.0)
	for e in ac.engines:
		_was_running.append(e.running)
	if not ac.touchdown.is_connected(_on_touchdown):
		ac.touchdown.connect(_on_touchdown)

func _player(stream: AudioStream, bus: String, unit: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = bus
	p.unit_size = unit
	p.max_distance = 900.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_IDLE_STEP
	p.volume_db = -80.0
	p.attenuation_filter_cutoff_hz = 9000.0
	p.attenuation_filter_db = -18.0
	add_child(p)
	return p


## Pure mapping from simulated engine state to the audio layer settings (unit-tested).
## pitch/noise_pitch are playback-rate multipliers; level/nlevel are linear amplitudes.
## Each propulsion family has its own load/RPM law so they never sound alike:
##  electric  - motor whine that tracks RPM and swells under load
##  glow/gas  - exhaust note with a constant bark, louder with throttle, lopey at idle (4-stroke worst)
##  edf       - high fan whine + broadband intake noise growing with the square of spool
##  turbine   - low rumble and whine, quiet at idle (spool is slow), noise dominates at high power
static func layer_params(t: String, rpm: float, ref: float, load: float, rpm_frac: float, running: bool, health: float, time: float) -> Dictionary:
	var pitch := clampf(rpm / ref, 0.08, 3.5)
	var npitch := pitch
	var level := 0.0
	var nlevel := 0.0
	load = clampf(load, 0.0, 1.0)
	match t:
		"electric":
			level = clampf(rpm / 9000.0, 0.0, 1.2) * (0.35 + 0.65 * load)
			nlevel = clampf(rpm / 8000.0, 0.0, 1.3) * 0.8
			npitch = clampf(rpm / ref, 0.2, 2.5)
		"glow2", "glow4", "gas2":
			level = 0.55 + 0.45 * load
			if not running:
				level *= clampf(rpm / 1500.0, 0.0, 1.0) * 0.4
			nlevel = clampf(rpm / 9000.0, 0.0, 1.2) * 0.5
			npitch = clampf(rpm / 6000.0, 0.2, 2.5)
			if running and load < 0.3:
				# idle "lope": the engine hunts around its idle speed, strongest on a four-stroke
				var depth := (0.045 if t == "glow4" else (0.03 if t == "glow2" else 0.02)) * (0.3 - load) / 0.3
				pitch *= 1.0 + depth * sin(time * TAU * (1.3 if t == "glow4" else 2.1)) + depth * 0.5 * sin(time * TAU * 3.7)
		"edf":
			level = clampf(rpm_frac * 1.3, 0.0, 1.2)
			nlevel = rpm_frac * rpm_frac * 1.2
			npitch = 0.6 + rpm_frac * 0.7
		"turbine":
			level = clampf(rpm_frac * 1.1, 0.0, 1.0)
			nlevel = clampf((rpm_frac - 0.3) * 1.6, 0.05, 1.3)
			npitch = 0.7 + rpm_frac * 0.5
	# damaged prop buzzes harder and rougher
	if health < 0.95 and t in ["electric", "glow2", "glow4", "gas2"]:
		nlevel *= 1.0 + (1.0 - health) * 2.0
		pitch *= 1.0 + sin(time * 50.0) * 0.02 * (1.0 - health)
	return {"pitch": pitch, "noise_pitch": npitch, "level": level, "nlevel": nlevel}

func _on_touchdown(info: Dictionary) -> void:
	if not is_instance_valid(ac) or ac.replay_driven:
		return
	var vs := clampf(float(info.get("vs", 0.0)), 0.0, 6.0)
	var sp := clampf(float(info.get("speed", 0.0)) / 20.0, 0.1, 1.0)
	Sfx.play3d("tire_chirp", info.get("pos", ac.global_position), clampf(0.25 + vs * 0.18, 0.2, 1.0) * sp + 0.1, randf_range(0.9, 1.15))

func _process(delta: float) -> void:
	if ac == null or not is_instance_valid(ac) or layers.is_empty():
		return
	if not started:
		started = true
		for l in layers:
			(l["tone"] as AudioStreamPlayer3D).play()
			(l["noise"] as AudioStreamPlayer3D).play()
		wind.play()
		roll.play()
		scrape.play()
		servo.play()
		gear_motor.play()
		brake_squeal.play()
	if _replay_was_active != ac.replay_driven:
		_replay_was_active = ac.replay_driven
		for child in get_children():
			if child is AudioStreamPlayer3D:
				child.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED if ac.replay_driven else AudioStreamPlayer3D.DOPPLER_TRACKING_IDLE_STEP
	var rate := ac.replay_rate if ac.replay_driven else 1.0
	var paused := (get_tree().paused and not ac.replay_driven) or rate <= 0.0
	for ei in layers.size():
		var l: Dictionary = layers[ei]
		var e: Propulsion = ac.engines[ei]
		var tone: AudioStreamPlayer3D = l["tone"]
		var noise: AudioStreamPlayer3D = l["noise"]
		var rpm := e.rpm()
		var ref := float(Sfx.REF.get(l["type"], 6000.0))
		var t := String(l["type"])
		var ci := int(ac.eng_defs[ei]["comp"])
		var detached: bool = ac.replay_owners[ci] >= 0 if ac.replay_driven and ci < ac.replay_owners.size() else ac.comps[ci]["detached"]
		if paused or rpm < 30.0 or detached:
			tone.volume_db = -80.0
			noise.volume_db = -80.0
			continue
		var tnow := ac.replay_time if ac.replay_driven else ac.sim_t
		var lp := layer_params(t, rpm, ref, e.thr_cmd, e.rpm_frac, e.running, e.health, tnow)
		tone.pitch_scale = maxf(0.05, float(lp["pitch"]) * rate)
		noise.pitch_scale = maxf(0.05, float(lp["noise_pitch"]) * rate)
		var level: float = lp["level"]
		var nlevel: float = lp["nlevel"]
		tone.volume_db = linear_to_db(maxf(level, 0.0005)) + 2.0
		noise.volume_db = linear_to_db(maxf(nlevel, 0.0005)) - 2.0
	# airframe wind noise
	var spd := ac.airspeed
	wind.volume_db = linear_to_db(clampf(spd * spd / 900.0, 0.0005, 1.3)) - 4.0
	wind.pitch_scale = maxf(0.05, clampf(0.6 + spd / 40.0, 0.5, 2.0) * rate)
	# tyres
	var rolling := 0.0
	var surf := 0
	for w in ac.wheels:
		if w["contact"]:
			rolling = maxf(rolling, absf(float(w["spin_rate"]) * float(w["r"])))
			surf = int(w["surface"])
	if surf != last_surface:
		last_surface = surf
		roll.stream = Sfx.bank["roll_grass"] if surf in [0, 6] else Sfx.bank["roll_asphalt"]
		roll.play()
	roll.volume_db = linear_to_db(clampf(rolling / 12.0, 0.0005, 1.0)) - 6.0
	roll.pitch_scale = maxf(0.05, clampf(0.6 + rolling / 15.0, 0.5, 2.0) * rate)
	scrape.pitch_scale = maxf(0.05, rate)
	scrape.volume_db = linear_to_db(clampf(ac.scrape_level, 0.0005, 1.0))
	# servos: loudness follows how hard the control surfaces are being driven
	var dt := maxf(delta, 1e-4)
	if _prev_defl.size() != ac.surfaces.size():
		_prev_defl.clear()
		for sf in ac.surfaces:
			_prev_defl.append(float(sf["defl"]))
	var moved := 0.0
	for si in ac.surfaces.size():
		var d := float(ac.surfaces[si]["defl"])
		if not ac.surfaces[si]["dead"]:
			moved += absf(d - float(_prev_defl[si])) / dt
		_prev_defl[si] = d
	var servo_norm := clampf(moved / maxf(deg_to_rad(ac.servo_speed) * 2.5, 0.1), 0.0, 1.0)
	_servo_act = lerpf(_servo_act, servo_norm, clampf(dt * 14.0, 0.0, 1.0))
	servo.volume_db = linear_to_db(clampf(_servo_act * 0.5, 0.0005, 0.6)) if _servo_act > 0.02 else -80.0
	servo.pitch_scale = maxf(0.05, (0.9 + 0.3 * _servo_act) * rate)
	# retract actuator while the gear travels, a mechanical lock thunk when it arrives
	var gp := ac.gear_pos
	var moving_gear := ac.has_retracts() and gp > 0.01 and gp < 0.99 and absf(gp - _prev_gear) > 1e-5
	gear_motor.volume_db = -14.0 if moving_gear else -80.0
	gear_motor.pitch_scale = maxf(0.05, (0.95 + 0.1 * sin(gp * 9.0)) * rate)
	if ac.has_retracts() and not ac.replay_driven and ((_prev_gear > 0.0 and gp <= 0.0) or (_prev_gear < 1.0 and gp >= 1.0)):
		Sfx.play3d("gear_lock", ac.global_position + ac.global_transform.basis.y * -0.1, 0.5, randf_range(0.9, 1.1))
	_prev_gear = gp
	# tyre squeal under hard braking while rolling fast
	var braking := ac.brake > 0.6 and ac.ground_speed > 4.0 and ac.wheels_touching > 0
	brake_squeal.volume_db = linear_to_db(clampf(ac.brake * clampf(ac.ground_speed / 15.0, 0.0, 1.0) * 0.45, 0.0005, 0.6)) if braking else -80.0
	brake_squeal.pitch_scale = maxf(0.05, (0.85 + clampf(ac.ground_speed / 40.0, 0.0, 0.5)) * rate)
	# ESC arm/disarm tune (electric / EDF)
	for ei in ac.engines.size():
		var e2: Propulsion = ac.engines[ei]
		if ei < _was_running.size() and e2.running != _was_running[ei]:
			if e2.type in ["electric", "edf"] and e2.running and not ac.replay_driven:
				Sfx.play3d("esc_arm", ac.global_position, 0.35, 1.0)
			_was_running[ei] = e2.running
	if paused:
		wind.volume_db = -80.0
		roll.volume_db = -80.0
		scrape.volume_db = -80.0
		servo.volume_db = -80.0
		gear_motor.volume_db = -80.0
		brake_squeal.volume_db = -80.0
