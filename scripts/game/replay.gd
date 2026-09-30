class_name Replay
extends Node
## Bounded rolling flight history plus a pinned crash clip. A replay session is
## distinct from its transport state: pause/end/seek never discard the live save.

const HZ := 60.0
const MAX_FRAMES := 1560
const CRASH_LEAD := 6.0
const CRASH_TAIL := 12.0
const MAX_PINNED := 1100
const MAX_SOUNDS := 512
var frames: Array = []
var head := 0
var count := 0
var ac: Aircraft
var fx: Fx
var npcs: Array = []
var recording := true
var playing := false
var session_active := false
var paused := false
var finished := false
var play_t := 0.0
var t0 := 0.0
var t1 := 0.0
var speed := 1.0
var slow_center := -1.0
var slow_factor := 0.3
var loop := false
var pinned: Array = []
var pinned_sounds: Array = []
var sound_events: Array = []
var pin_until := -1.0
var pin_time := -1.0
var using_pinned := false
var _last_record := -100.0
var _last_time := 0.0
var _saved_aircraft: Dictionary = {}
var _saved_chips: Array = []
var _saved_npcs: Array = []
signal ended

func _init() -> void:
	frames.resize(MAX_FRAMES)
	process_mode = Node.PROCESS_MODE_ALWAYS

func bind(aircraft: Aircraft, effects: Fx, people: Array) -> void:
	ac = aircraft
	fx = effects
	npcs = people
	clear()

func clear() -> void:
	if session_active: stop()
	frames.fill(null)
	head = 0
	count = 0
	_last_record = -100.0
	pinned.clear()
	pinned_sounds.clear()
	sound_events.clear()
	pin_until = -1.0
	pin_time = -1.0
	using_pinned = false
	finished = false

func record(t: float) -> void:
	if not recording or session_active or ac == null: return
	_last_time = t
	if t - _last_record < 1.0 / HZ - 0.00001: return
	_last_record = t
	var f := {"t": t, "xf": ac.global_transform, "com": ac.com_local,
		"pa": PackedFloat32Array(ac.prop_angle), "wa": PackedFloat32Array(ac.wheel_spin_angle),
		"gear": ac.gear_pos, "speed": ac.airspeed, "scrape": ac.scrape_level,
		"ground": ac.on_ground, "throttle": ac.in_throttle}
	var defl := PackedFloat32Array()
	for surface in ac.surfaces: defl.append(float(surface["defl"]))
	f["defl"] = defl
	var om := PackedFloat32Array()
	var rf := PackedFloat32Array()
	var eh := PackedFloat32Array()
	var et := PackedFloat32Array()
	var er := PackedByteArray()
	for engine in ac.engines:
		om.append(engine.omega)
		rf.append(engine.rpm_frac)
		eh.append(engine.health)
		et.append(engine.thr_cmd)
		er.append(1 if engine.running else 0)
	f["om"] = om
	f["rf"] = rf
	f["eh"] = eh
	f["et"] = et
	f["er"] = er
	var wh := PackedFloat32Array()
	var wc := PackedByteArray()
	var wsurface := PackedInt32Array()
	for wheel in ac.wheels:
		wh.append(float(wheel["comp_now"]))
		wh.append(float(wheel["spin_rate"]))
		wh.append(float(wheel.get("steer_now", 0.0)))
		wc.append(1 if wheel.get("contact", false) else 0)
		wsurface.append(int(wheel.get("surface", 0)))
	f["wh"] = wh
	f["wc"] = wc
	f["wsurface"] = wsurface
	var owners := PackedInt32Array()
	var dmg := PackedFloat32Array()
	var dirt := PackedFloat32Array()
	var dx := {}
	for component in ac.comps:
		owners.append(int(component["debris"]) if component["detached"] else -1)
		dmg.append(float(component["dmg_vis"]))
		dirt.append(float(component["dirt"]))
	for i in ac.debris_bodies.size():
		var rb: RigidBody3D = ac.debris_bodies[i]
		if rb and not (rb.get_meta("members", []) as Array).is_empty():
			dx[i] = rb.global_transform
	f["own"] = owners
	f["dmg"] = dmg
	f["dirt"] = dirt
	f["dx"] = dx
	if fx:
		var chips := []
		for i in fx.chips.size():
			var chip: RigidBody3D = fx.chips[i]
			if chip.visible: chips.append([i, chip.global_transform])
		f["ch"] = chips
	var people := []
	for person in npcs: people.append(person.global_transform)
	f["np"] = people
	frames[head] = f
	head = (head + 1) % MAX_FRAMES
	count = mini(count + 1, MAX_FRAMES)
	if pin_until >= t and pinned.size() < MAX_PINNED:
		# Frames are never mutated after capture, so retaining the dictionary is safe.
		pinned.append(f)

func pin_crash(t: float) -> void:
	pinned.clear()
	pinned_sounds.clear()
	pin_time = t
	pin_until = t + CRASH_TAIL
	for i in count:
		var f := _ring_at(i)
		if float(f["t"]) >= t - CRASH_LEAD: pinned.append(f)
	for event in sound_events:
		if float(event[0]) >= t - CRASH_LEAD: pinned_sounds.append(event)

func record_sound(sound: String, pos: Vector3, volume: float, pitch: float) -> void:
	if not recording or session_active: return
	var event := [_last_time, sound, pos, volume, pitch]
	sound_events.append(event)
	while sound_events.size() > MAX_SOUNDS or (not sound_events.is_empty() and float(sound_events[0][0]) < _last_time - 26.0):
		sound_events.pop_front()
	if pin_until >= _last_time and pinned_sounds.size() < MAX_SOUNDS:
		pinned_sounds.append(event)

func _ring_at(i: int) -> Dictionary:
	return frames[(head - count + i + MAX_FRAMES) % MAX_FRAMES]

func _size() -> int:
	return pinned.size() if using_pinned else count

func _at(i: int) -> Dictionary:
	return pinned[i] if using_pinned else _ring_at(i)

func oldest_t() -> float:
	return float(_at(0)["t"]) if _size() > 0 else 0.0

func newest_t() -> float:
	return float(_at(_size() - 1)["t"]) if _size() > 0 else 0.0

func truncate_after(t: float) -> void:
	using_pinned = false
	pinned.clear()
	pinned_sounds.clear()
	pin_until = -1.0
	pin_time = -1.0
	while count > 0 and float(_ring_at(count - 1)["t"]) > t:
		head = (head - 1 + MAX_FRAMES) % MAX_FRAMES
		frames[head] = null
		count -= 1
	while not sound_events.is_empty() and float(sound_events.back()[0]) > t:
		sound_events.pop_back()
	_last_record = t - 1.0 / HZ
	_last_time = t

func start(from_t: float, to_t: float, slow_at := -1.0) -> void:
	using_pinned = slow_at >= 0.0 and pinned.size() >= 2
	if _size() < 2: return
	t0 = clampf(from_t, oldest_t(), newest_t())
	t1 = clampf(to_t, t0, newest_t())
	if t1 <= t0: return
	if not session_active:
		_saved_aircraft = ac.snapshot()
		_saved_chips.clear()
		if fx:
			for chip in fx.chips:
				_saved_chips.append([chip.global_transform, chip.visible])
		_saved_npcs.clear()
		for person in npcs: _saved_npcs.append(person.global_transform)
	session_active = true
	playing = true
	paused = false
	finished = false
	play_t = t0
	slow_center = slow_at
	ac.replay_driven = true
	Sfx.stop_replay_sounds()
	apply(play_t)

func stop() -> void:
	if not session_active: return
	playing = false
	paused = false
	session_active = false
	Sfx.stop_replay_sounds()
	ac.replay_driven = false
	ac.replay_rate = 0.0
	ac.restore(_saved_aircraft)
	if fx:
		for i in mini(_saved_chips.size(), fx.chips.size()):
			fx.chips[i].global_transform = _saved_chips[i][0]
			fx.chips[i].visible = _saved_chips[i][1]
	for i in mini(_saved_npcs.size(), npcs.size()):
		npcs[i].global_transform = _saved_npcs[i]
	_saved_aircraft.clear()
	_saved_chips.clear()
	_saved_npcs.clear()

func finish() -> void:
	play_t = t1
	playing = false
	paused = false
	finished = true
	ac.replay_rate = 0.0
	apply(play_t)
	Sfx.stop_replay_sounds()

func progress() -> float:
	return clampf((play_t - t0) / maxf(t1 - t0, 0.001), 0.0, 1.0)

func seek(frac: float) -> void:
	if not session_active: return
	play_t = lerpf(t0, t1, clampf(frac, 0.0, 1.0))
	finished = false
	playing = true
	paused = true
	ac.replay_rate = 0.0
	Sfx.stop_replay_sounds()
	apply(play_t)

func current_rate() -> float:
	var rate := speed
	if slow_center >= 0.0:
		var d := play_t - slow_center
		var weight := 1.0 - smoothstep(0.2, 1.4, absf(d + 0.45))
		rate *= lerpf(1.0, slow_factor, weight)
	return rate

func _process(delta: float) -> void:
	if ac and session_active:
		ac.replay_rate = current_rate() if playing and not paused else 0.0
	if not playing or paused or ac == null: return
	var old := play_t
	play_t = minf(play_t + delta * current_rate(), t1)
	apply(play_t)
	var events: Array = pinned_sounds if using_pinned else sound_events
	for event in events:
		if float(event[0]) > old and float(event[0]) <= play_t:
			Sfx.play_replay_sound(event[1], event[2], event[3], event[4], current_rate())
	if play_t >= t1:
		if loop:
			play_t = t0
			Sfx.stop_replay_sounds()
		else:
			finish()
			ended.emit()

func _find(t: float) -> int:
	var low := 0
	var high := _size() - 1
	while low < high:
		var mid := (low + high + 1) / 2
		if float(_at(mid)["t"]) <= t: low = mid
		else: high = mid - 1
	return low

func apply(t: float) -> void:
	if _size() < 2: return
	var i := _find(t)
	var fa := _at(i)
	var fb := _at(mini(i + 1, _size() - 1))
	var weight := clampf((t - float(fa["t"])) / maxf(float(fb["t"]) - float(fa["t"]), 1e-5), 0.0, 1.0)
	ac.apply_replay(fa, fb, weight, 0.0)
	ac.replay_time = t
	if fx:
		for chip in fx.chips: chip.visible = false
		for chip in fa.get("ch", []):
			var index := int(chip[0])
			if index < 0 or index >= fx.chips.size(): continue
			fx.chips[index].visible = true
			fx.chips[index].global_transform = chip[1]
	var people: Array = fa["np"]
	var next_people: Array = fb["np"]
	for k in mini(mini(people.size(), next_people.size()), npcs.size()):
		npcs[k].global_transform = (people[k] as Transform3D).interpolate_with(next_people[k], weight)

func focus_at(t: float) -> Vector3:
	if _size() < 1: return Vector3.ZERO
	var f := _at(_find(t))
	return (f["xf"] as Transform3D) * (f.get("com", ac.com_local) as Vector3)

func frame_xf(t: float) -> Transform3D:
	return _at(_find(t))["xf"] if _size() > 0 else Transform3D()

func velocity_at(t: float) -> Vector3:
	if _size() < 3: return Vector3.ZERO
	var i := _find(t)
	var a := _at(maxi(i - 1, 0))
	var b := _at(mini(i + 1, _size() - 1))
	var dt := float(b["t"]) - float(a["t"])
	return ((b["xf"] as Transform3D).origin - (a["xf"] as Transform3D).origin) / dt if dt > 0.0 else Vector3.ZERO
