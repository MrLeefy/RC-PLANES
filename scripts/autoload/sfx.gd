extends Node
## Procedurally synthesised sound bank (no licensed samples needed) + pooled players.
## Engine loops are generated once at a reference RPM and pitch-shifted by the
## simulated RPM; one-shots are pooled so crashes never allocate audio.

const RATE := 22050
const CACHE_DIR := "user://sfx_cache_v3"

var bank: Dictionary = {}
var ready_flag := false
var pool3d: Array = []
var pool_i := 0
var pool2d: Array = []
var pool2d_i := 0
var ambience: AudioStreamPlayer
var buses_ready := false
signal world_sound(sound: String, pos: Vector3, volume: float, pitch: float)
var replay_output := false
var replay_transport_active := false
var replay_transport_rate := 0.0

# reference rpm each loop was synthesised at
const REF := {"electric": 6000.0, "edf": 30000.0, "glow2": 9000.0, "glow4": 9000.0, "gas2": 7000.0, "turbine": 100000.0}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()

func _setup_buses() -> void:
	if buses_ready:
		return
	for b in ["Engine", "SFX", "Ambience", "UI"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	# gentle limiter on master so big crashes don't clip
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.5
	AudioServer.add_bus_effect(0, lim)
	buses_ready = true
	apply_volumes()

func apply_volumes() -> void:
	var a: Dictionary = Settings.data.get("audio", {})
	_set_bus("Master", float(a.get("master", 0.9)))
	_set_bus("Engine", float(a.get("engine", 1.0)))
	_set_bus("SFX", float(a.get("effects", 1.0)))
	_set_bus("Ambience", float(a.get("ambience", 0.6)))
	_set_bus("UI", float(a.get("effects", 1.0)) * 0.7)

func _set_bus(name: String, v: float) -> void:
	var i := AudioServer.get_bus_index(name)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001)

## Build (or load cached) sound bank. Yields between sounds to keep the loading screen alive.
func build_bank_async(progress: Callable) -> void:
	var names := ["electric", "edf", "edf_noise", "glow2", "glow4", "gas2", "turbine", "turbine_roar", "prop_swish",
		"wind", "ambience", "scrape", "roll_asphalt", "roll_grass", "impact_foam", "impact_wood", "impact_composite",
		"impact_metal", "thud", "gear", "branch", "starter", "click", "beep", "leaves"]
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var i := 0
	for n in names:
		var path := "%s/%s.res" % [CACHE_DIR, n]
		var st: AudioStreamWAV = null
		if FileAccess.file_exists(path):
			st = load(path) as AudioStreamWAV
		if st == null:
			st = _synth(n)
			if st:
				ResourceSaver.save(st, path, ResourceSaver.FLAG_COMPRESS)
		bank[n] = st
		i += 1
		progress.call(float(i) / names.size(), "Tuning engines")
		if i % 3 == 0:
			await get_tree().process_frame
	# pooled one-shot players
	for k in 14:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"
		p.unit_size = 6.0
		p.max_distance = 400.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		add_child(p)
		pool3d.append(p)
	for k in 4:
		var p2 := AudioStreamPlayer.new()
		p2.bus = "UI"
		add_child(p2)
		pool2d.append(p2)
	ambience = AudioStreamPlayer.new()
	ambience.bus = "Ambience"
	ambience.stream = bank["ambience"]
	ambience.volume_db = -6.0
	add_child(ambience)
	ready_flag = true

func start_ambience() -> void:
	if ambience and not ambience.playing:
		ambience.play()

func play3d(name: String, pos: Vector3, vol := 1.0, pitch := 1.0) -> void:
	if not ready_flag or not bank.has(name):
		return
	if get_tree().paused and not replay_output: return
	if not replay_output: world_sound.emit(name, pos, vol, pitch)
	var p: AudioStreamPlayer3D = pool3d[pool_i]
	p.set_meta("replay", replay_output)
	p.stream_paused = false
	pool_i = (pool_i + 1) % pool3d.size()
	p.stream = bank[name]
	p.global_position = pos
	p.volume_db = linear_to_db(clampf(vol, 0.001, 2.0))
	p.pitch_scale = clampf(pitch, 0.3, 3.0)
	p.play()

func ui(name := "click", vol := 0.6) -> void:
	if not ready_flag or not bank.has(name):
		return
	var p: AudioStreamPlayer = pool2d[pool2d_i]
	pool2d_i = (pool2d_i + 1) % pool2d.size()
	p.stream = bank[name]
	p.volume_db = linear_to_db(vol)
	p.play()

func play_replay_sound(sound: String, pos: Vector3, volume: float, pitch: float, rate: float) -> void:
	replay_output = true
	play3d(sound, pos, volume * 0.85, pitch * clampf(rate, 0.1, 2.0))
	replay_output = false

func stop_replay_sounds() -> void:
	for player in pool3d:
		if player.get_meta("replay", false):
			player.stop()
			player.stream_paused = false

func _process(_delta: float) -> void:
	for player in pool3d:
		if player.get_meta("replay", false):
			player.stream_paused = not replay_transport_active or replay_transport_rate <= 0.0
		else:
			player.stream_paused = get_tree().paused

# ================================================================ synthesis
var _rng := RandomNumberGenerator.new()

func _wav(data: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	var peak := 0.0001
	for v in data:
		peak = maxf(peak, absf(v))
	var g := 0.92 / peak
	for i in data.size():
		var s := int(clampf(data[i] * g, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, s)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = data.size()
	return w

func _noise_buf(n: int, seed_i: int) -> PackedFloat32Array:
	_rng.seed = seed_i
	var b := PackedFloat32Array()
	b.resize(n)
	for i in n:
		b[i] = _rng.randf_range(-1.0, 1.0)
	return b

## one-pole low-pass in place (circular so loops stay seamless)
func _lp(b: PackedFloat32Array, a: float, passes := 1) -> void:
	for p in passes:
		var y := b[b.size() - 1]
		for i in b.size():
			y += a * (b[i] - y)
			b[i] = y

func _hp(b: PackedFloat32Array, a: float) -> void:
	var lp := b.duplicate()
	_lp(lp, a)
	for i in b.size():
		b[i] = b[i] - lp[i]

func _synth(name: String) -> AudioStreamWAV:
	match name:
		"electric": return _electric()
		"edf": return _edf()
		"edf_noise": return _edf_noise()
		"glow2": return _ic(150.0, 1, 0.55, 0.25, 11)
		"glow4": return _ic(75.0, 2, 0.35, 0.12, 12)
		"gas2": return _ic(116.6667, 1, 0.8, 0.35, 13)
		"turbine": return _turbine()
		"turbine_roar": return _roar()
		"prop_swish": return _swish()
		"wind": return _wind()
		"ambience": return _ambience()
		"scrape": return _scrape()
		"roll_asphalt": return _roll(0.08, 21)
		"roll_grass": return _roll(0.25, 22)
		"impact_foam": return _impact(0.08, 0.35, 180.0, 31, 0.5)
		"impact_wood": return _impact(0.02, 0.2, 420.0, 32, 0.9)
		"impact_composite": return _impact(0.01, 0.35, 900.0, 33, 1.2)
		"impact_metal": return _metal()
		"thud": return _impact(0.12, 0.25, 90.0, 35, 0.2)
		"gear": return _impact(0.05, 0.18, 220.0, 36, 0.6)
		"branch": return _branch()
		"starter": return _starter()
		"click": return _click(0.02, 1600.0)
		"beep": return _click(0.12, 880.0)
		"leaves": return _leaves()
	return null

func _electric() -> AudioStreamWAV:
	# 6000 rpm reference: 100 rps; 7 pole pairs -> 700 Hz whine; 2 blades -> 200 Hz
	var n := RATE
	var out := PackedFloat32Array()
	out.resize(n)
	var nz := _noise_buf(n, 1)
	_lp(nz, 0.25)
	for i in n:
		var t := float(i) / RATE
		var whine := sin(TAU * 700.0 * t) * 0.35 + sin(TAU * 1400.0 * t) * 0.18 + sin(TAU * 2100.0 * t) * 0.08
		var bp := fposmod(t * 200.0, 1.0)
		var buzz := (exp(-bp * 6.0) - 0.3) * 0.55 + sin(TAU * 200.0 * t) * 0.25 + sin(TAU * 400.0 * t) * 0.12
		var sw := nz[i] * (0.3 + 0.7 * exp(-bp * 3.0))
		out[i] = whine * 0.5 + buzz + sw * 0.45
	return _wav(out, true)

func _edf() -> AudioStreamWAV:
	# 30000 rpm: 500 rps, 12 blades -> 6000 Hz + sub harmonics
	var n := RATE
	var out := PackedFloat32Array()
	out.resize(n)
	var nz := _noise_buf(n, 2)
	_lp(nz, 0.5)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * 6000.0 * t) * 0.25 + sin(TAU * 3000.0 * t) * 0.18 + sin(TAU * 500.0 * t) * 0.1 + nz[i] * 0.55
	return _wav(out, true)

func _edf_noise() -> AudioStreamWAV:
	var n := RATE * 2
	var nz := _noise_buf(n, 3)
	_lp(nz, 0.18, 2)
	return _wav(nz, true)

func _ic(fire_hz: float, strokes: int, rough: float, clatter: float, seed_i: int) -> AudioStreamWAV:
	# exhaust pulse train: each firing = sharp pressure pulse + ringing muffler + noise
	var n := RATE
	var out := PackedFloat32Array()
	out.resize(n)
	var nz := _noise_buf(n, seed_i)
	_lp(nz, 0.6)
	_rng.seed = seed_i * 3
	var period := 1.0 / fire_hz
	var cycles := int(round(1.0 * fire_hz))
	var amps := PackedFloat32Array()
	for c in cycles + 1:
		amps.append(1.0 + _rng.randf_range(-rough, rough) * 0.35)
	for i in n:
		var t := float(i) / RATE
		var cyc := int(floor(t / period))
		var ph := fposmod(t, period) / period
		var a: float = amps[mini(cyc, cycles)]
		var pulse := exp(-ph * (14.0 if strokes == 1 else 9.0)) * a
		var ring := sin(TAU * ph * (5.0 if strokes == 1 else 3.2)) * exp(-ph * 4.0) * 0.5 * a
		var hiss := nz[i] * exp(-ph * 5.0) * (0.55 + rough * 0.4)
		var clk := 0.0
		if clatter > 0.0:
			var ph2 := fposmod(t * fire_hz * 2.0, 1.0)
			clk = nz[(i * 7) % n] * exp(-ph2 * 40.0) * clatter
		out[i] = pulse * 0.9 + ring + hiss + clk - 0.2
	_hp(out, 0.02)
	return _wav(out, true)

func _turbine() -> AudioStreamWAV:
	var n := RATE
	var out := PackedFloat32Array()
	out.resize(n)
	var nz := _noise_buf(n, 5)
	_lp(nz, 0.35)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * 3200.0 * t) * 0.3 + sin(TAU * 1600.0 * t) * 0.2 + sin(TAU * 4800.0 * t) * 0.1 + nz[i] * 0.4
	return _wav(out, true)

func _roar() -> AudioStreamWAV:
	var n := RATE * 2
	var nz := _noise_buf(n, 6)
	_lp(nz, 0.08, 2)
	var nz2 := _noise_buf(n, 7)
	_lp(nz2, 0.3)
	for i in n:
		nz[i] = nz[i] * 1.5 + nz2[i] * 0.3
	return _wav(nz, true)

func _swish() -> AudioStreamWAV:
	var n := RATE
	var nz := _noise_buf(n, 8)
	_lp(nz, 0.4)
	for i in n:
		var t := float(i) / RATE
		var bp := fposmod(t * 200.0, 1.0)
		nz[i] *= 0.35 + 0.65 * exp(-bp * 3.5)
	return _wav(nz, true)

func _wind() -> AudioStreamWAV:
	var n := RATE * 2
	var nz := _noise_buf(n, 9)
	_lp(nz, 0.06, 2)
	var mod := _noise_buf(n, 10)
	_lp(mod, 0.0008, 2)
	for i in n:
		nz[i] *= 0.7 + mod[i] * 6.0
	return _wav(nz, true)

func _ambience() -> AudioStreamWAV:
	var n := RATE * 6
	var out := _noise_buf(n, 11)
	_lp(out, 0.02, 2)
	for i in n:
		out[i] *= 0.6
	# birds: chirp sweeps at random times
	_rng.seed = 12
	for k in 16:
		var start := _rng.randi_range(0, n - RATE / 2)
		var f0 := _rng.randf_range(2200.0, 4200.0)
		var chirps := _rng.randi_range(2, 5)
		for c in chirps:
			var st := start + c * int(RATE * _rng.randf_range(0.08, 0.14))
			var ln := int(RATE * _rng.randf_range(0.04, 0.09))
			var ph := 0.0
			for j in ln:
				if st + j >= n:
					break
				var tt := float(j) / ln
				var f := f0 * (1.0 + 0.35 * sin(tt * PI)) * (1.0 - 0.2 * tt)
				ph += TAU * f / RATE
				out[st + j] += sin(ph) * sin(tt * PI) * 0.12
	# crossfade ends for a seamless loop
	var xf := RATE / 4
	for i in xf:
		var a := float(i) / xf
		out[i] = out[i] * a + out[n - xf + i] * (1.0 - a)
	out.resize(n - xf)
	return _wav(out, true)

func _scrape() -> AudioStreamWAV:
	var n := RATE
	var nz := _noise_buf(n, 14)
	_hp(nz, 0.1)
	var grit := _noise_buf(n, 15)
	for i in n:
		var g := 1.0 if grit[i] > 0.93 else 0.2
		nz[i] *= g
	_lp(nz, 0.5)
	return _wav(nz, true)

func _roll(lp: float, seed_i: int) -> AudioStreamWAV:
	var n := RATE
	var nz := _noise_buf(n, seed_i)
	_lp(nz, lp, 2)
	return _wav(nz, true)

func _impact(attack: float, decay: float, body_hz: float, seed_i: int, crack: float) -> AudioStreamWAV:
	var n := int(RATE * (decay * 3.0 + 0.1))
	var out := _noise_buf(n, seed_i)
	var nz2 := out.duplicate()
	_lp(out, 0.3 if crack > 0.8 else 0.12)
	for i in n:
		var t := float(i) / RATE
		var env := (1.0 - exp(-t / maxf(attack * 0.2, 0.0005))) * exp(-t / decay)
		var body := sin(TAU * body_hz * t * (1.0 - t * 0.5)) * exp(-t / (decay * 0.6))
		var cr := nz2[i] * exp(-t / 0.015) * crack
		out[i] = out[i] * env + body * 0.8 + cr
	return _wav(out, false)

func _metal() -> AudioStreamWAV:
	var n := int(RATE * 0.8)
	var out := PackedFloat32Array()
	out.resize(n)
	var partials := [410.0, 1123.0, 1789.0, 2610.0, 3377.0]
	var nz := _noise_buf(n, 40)
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for k in partials.size():
			s += sin(TAU * partials[k] * t) * exp(-t * (4.0 + k * 3.0)) / (k + 1)
		out[i] = s + nz[i] * exp(-t * 60.0) * 0.8
	return _wav(out, false)

func _branch() -> AudioStreamWAV:
	var n := int(RATE * 0.4)
	var out := _noise_buf(n, 41)
	for i in n:
		var t := float(i) / RATE
		var cr := 1.0 if (int(t * 180.0) % 3 == 0 and t < 0.08) else 0.3
		out[i] *= exp(-t * 18.0) * cr
	return _wav(out, false)

func _starter() -> AudioStreamWAV:
	var n := int(RATE * 1.3)
	var out := PackedFloat32Array()
	out.resize(n)
	var nz := _noise_buf(n, 42)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 60.0 + 380.0 * minf(t / 0.4, 1.0)
		ph += TAU * f / RATE
		var comp := fposmod(ph / TAU * 0.5, 1.0)
		out[i] = sin(ph) * 0.5 + sin(ph * 3.0) * 0.2 + nz[i] * 0.15 * exp(-comp * 6.0)
		out[i] *= minf(t / 0.05, 1.0) * minf((1.3 - t) / 0.1, 1.0)
	return _wav(out, false)

func _click(len_s: float, f: float) -> AudioStreamWAV:
	var n := int(RATE * len_s)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * f * t) * exp(-t / (len_s * 0.35))
	return _wav(out, false)

func _leaves() -> AudioStreamWAV:
	var n := int(RATE * 0.7)
	var out := _noise_buf(n, 43)
	_hp(out, 0.2)
	var m := _noise_buf(n, 44)
	for i in n:
		var t := float(i) / RATE
		out[i] *= (0.4 + (1.0 if m[i] > 0.7 else 0.0)) * sin(PI * t / 0.7)
	return _wav(out, false)
