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
var started := false
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

func _process(_delta: float) -> void:
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
		var p := clampf(rpm / ref, 0.08, 3.5)
		tone.pitch_scale = maxf(0.05, p * rate)
		var load := clampf(e.thr_cmd, 0.0, 1.0)
		var level := 0.0
		var nlevel := 0.0
		match t:
			"electric":
				level = clampf(rpm / 9000.0, 0.0, 1.2) * (0.35 + 0.65 * load)
				nlevel = clampf(rpm / 8000.0, 0.0, 1.3) * 0.8
				noise.pitch_scale = clampf(rpm / ref, 0.2, 2.5)
			"glow2", "glow4", "gas2":
				level = 0.55 + 0.45 * load
				if not e.running:
					level *= clampf(rpm / 1500.0, 0.0, 1.0) * 0.4
				nlevel = clampf(rpm / 9000.0, 0.0, 1.2) * 0.5
				noise.pitch_scale = clampf(rpm / 6000.0, 0.2, 2.5)
			"edf":
				level = clampf(e.rpm_frac * 1.3, 0.0, 1.2)
				nlevel = e.rpm_frac * e.rpm_frac * 1.2
				noise.pitch_scale = 0.6 + e.rpm_frac * 0.7
			"turbine":
				level = clampf(e.rpm_frac * 1.1, 0.0, 1.0)
				nlevel = clampf((e.rpm_frac - 0.3) * 1.6, 0.05, 1.3)
				noise.pitch_scale = 0.7 + e.rpm_frac * 0.5
		noise.pitch_scale = maxf(0.05, noise.pitch_scale * rate)
		# damaged prop buzzes harder and rougher
		if e.health < 0.95 and e.is_prop():
			nlevel *= 1.0 + (1.0 - e.health) * 2.0
			tone.pitch_scale *= 1.0 + sin((ac.replay_time if ac.replay_driven else ac.sim_t) * 50.0) * 0.02 * (1.0 - e.health)
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
	if paused:
		wind.volume_db = -80.0
		roll.volume_db = -80.0
		scrape.volume_db = -80.0