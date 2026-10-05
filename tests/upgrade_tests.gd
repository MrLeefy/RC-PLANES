extends "res://tests/test_runner.gd"
## Production-code regressions for 0.10.0. Run in an isolated XDG_DATA_HOME:
## godot --headless --fixed-fps 120 --path . -- --upgrade-test
## No frame-time result here is an Android GPU, thermal, or touch-latency result.

class ContactProbe extends RigidBody3D:
	var normals: Array = []
	func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
		if normals.is_empty() and state.get_contact_count() > 0:
			normals.append(state.get_contact_local_normal(0))

func _run_all() -> void:
	await super._run_all()
	t_scale()
	t_store_and_validation()
	t_ghost_validation()
	t_foliage_index()
	await t_touch_and_safe_area()
	await t_snapshot_transport()
	await t_camera_regression()
	await t_rotated_contact_coordinates()
	await t_quality_roundtrip()
	await t_production_loop()

func t_scale() -> void:
	for fps in [30, 60, 90, 120]:
		var scale := AdaptiveScale.new()
		scale.configure(0.9, fps)
		scale.scale = 0.6
		for i in fps * 22: scale.update(1.0 / float(fps), 0.001)
		_ok("scale: recovers at capped %d FPS" % fps, scale.scale > 0.6 and scale.scale <= 0.9, str(scale.scale))
	var s := AdaptiveScale.new()
	s.configure(0.6, 60, true)
	_ok("scale: Ultra has explicit 0.95 quality ceiling", is_equal_approx(s.ceiling, 0.95))
	for i in 4000: s.update(1.0 / 25.0, 0.001)
	_ok("scale: overload respects 0.5 floor", is_equal_approx(s.scale, 0.5))
	s.configure(0.85, 60)
	for i in 900: s.update(1.0 / 25.0, 0.025)
	_ok("scale: physics bottleneck does not destroy pixel quality", is_equal_approx(s.scale, 0.85))
	s.update(NAN)
	_ok("scale: invalid timing resets sampling without NaN", is_finite(s.scale) and s.samples == 0)

func t_store_and_validation() -> void:
	var path := "user://upgrade_store_test.json"
	var a := SafeStore.write_json(path, {"zero": 0, "generation": 1})
	var b := SafeStore.write_json(path, {"zero": 0, "generation": 2})
	var previous := SafeStore.read_json(path + ".bak")
	var now := SafeStore.read_json(path)
	_ok("save: verified replace retains previous valid backup", a.get("ok", false) and b.get("ok", false) and previous.get("data", {}).get("generation") == 1 and now.get("data", {}).get("generation") == 2)
	var bad := SafeStore.write_json("/proc/rcpark-cannot-write/settings.json", {"x": 1})
	_ok("save: write failure returns error, not a success path", not bad.get("ok", false) and not bad.has("path"))
	var clean := Settings.validate({"controls":{"mode":"bad", "stick_size":NAN}, "graphics":{"fps":0,"grass":0},
		"transmitter":{"profiles":{"Broken":{"roll":[], "smoothing":"invalid"}}}, "records":{"bad":[],"good":2.0}})
	_ok("save: malformed nested profiles and non-finite fields are bounded", is_finite(float(clean["controls"]["stick_size"])) and clean["transmitter"]["profiles"]["Broken"]["roll"] is Dictionary and not clean["records"].has("bad"))
	_ok("save: zero density and Unlimited FPS survive validation", clean["graphics"]["grass"] == 0 and clean["graphics"]["fps"] == 0)
	var keep := Settings.data.duplicate(true)
	SafeStore.write_json(Settings.SAVE_PATH, {"version": 999, "preserve": "future"})
	Settings.load_settings()
	var before := FileAccess.get_file_as_string(Settings.SAVE_PATH)
	var wrote := Settings.save()
	_ok("save: newer schema remains read-only and byte-preserved", Settings.future_version and not wrote and FileAccess.get_file_as_string(Settings.SAVE_PATH) == before)
	Settings.future_version = false
	Settings.data = keep
	Settings.save()
	Settings.data["graphics"]["grass"] = 0.0
	Settings.save()
	# Primary corrupt, valid backup; loading must recover instead of silently reset.
	var f := FileAccess.open(Settings.SAVE_PATH, FileAccess.WRITE)
	f.store_string("{truncated"); f.close()
	Settings.load_settings()
	_ok("save: corrupt primary recovers the valid backup", Settings.load_status == "recovered_bak")
	Settings.data = keep
	Settings.save()

func t_ghost_validation() -> void:
	var track := [[0.0, Transform3D()], [1.0, Transform3D(Basis(), Vector3(2,3,4))]]
	var data := GhostCodec.encode(track, "setup-a", 1.0)
	_ok("ghost: valid setup-specific track round trips", GhostCodec.decode(data, "setup-a").get("ok", false))
	_ok("ghost: another aircraft/setup is rejected", not GhostCodec.decode(data, "setup-b").get("ok", false))
	var bad := data.duplicate(true)
	bad["track"][0] = [0.0, 1.0]
	_ok("ghost: short row rejected before indexing", not GhostCodec.decode(bad, "setup-a").get("ok", false))
	bad = data.duplicate(true); bad["track"][1][0] = 0.0
	_ok("ghost: non-monotonic times rejected", not GhostCodec.decode(bad, "setup-a").get("ok", false))
	bad = data.duplicate(true); bad["track"][1][7] = 0.0
	_ok("ghost: invalid quaternion rejected", not GhostCodec.decode(bad, "setup-a").get("ok", false))
	bad = data.duplicate(true); bad["track"][1][1] = INF
	_ok("ghost: non-finite transform rejected", not GhostCodec.decode(bad, "setup-a").get("ok", false))
	_ok("ghost: binary search includes final frame", GhostCodec.index_at(track, 2.0) == 1)

func t_foliage_index() -> void:
	var index := FoliageIndex.new()
	index.add(Vector3(49, 10, 0), 3.0, 1.0)
	var found: Array = []
	index.query(Vector3(47,10,0), 0.5, found)
	_ok("canopy: collision query crosses spatial bucket boundary", found.size() == 1)
	index.query(Vector3(49,16,0), 0.5, found)
	_ok("canopy: no phantom collision above visible crown", found.is_empty())
	index.query(Vector3(49,2,0), 0.5, found)
	_ok("canopy: no phantom collision below visible crown", found.is_empty())
	_ok("canopy: outer forest has collision descriptors", field.outer_canopies.count > 0, str(field.outer_canopies.count))

func _touch(index: int, pressed: bool, at := Vector2(20,20), canceled := false) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index; event.pressed = pressed; event.position = at; event.canceled = canceled
	return event

func t_touch_and_safe_area() -> void:
	var btn := TouchButton.new("TEST")
	get_parent().ui.add_child(btn)
	var taps := [0]
	btn.tapped.connect(func(): taps[0] += 1)
	btn._gui_input(_touch(2, true))
	btn._input(_touch(2, false, Vector2(20,20), true))
	_ok("touch: canceled button releases hold without tapping", taps[0] == 0 and not btn.active and btn._idx == -1)
	btn._gui_input(_touch(2, true))
	btn._input(_touch(2, false, Vector2(10000,10000)))
	_ok("touch: out-of-bounds release clears owner without tapping", taps[0] == 0 and btn._idx == -1)
	btn._gui_input(_touch(3, true)); btn.hide()
	_ok("touch: hiding control releases held pointer", not btn.active and btn._idx == -1)
	btn.queue_free()
	var gesture := OrbitGesture.new()
	get_parent().ui.add_child(gesture)
	var motion := [Vector2.ZERO, 1.0]
	gesture.orbit.connect(func(d): motion[0] += d)
	gesture.zoom.connect(func(z): motion[1] *= z)
	gesture._gui_input(_touch(0, true, Vector2(10,10)))
	var drag := InputEventScreenDrag.new()
	drag.index = 0; drag.position = Vector2(30,20); gesture._gui_input(drag)
	_ok("orbit: one-finger drag rotates and updates stored position", motion[0] == Vector2(20,10) and gesture.points[0] == Vector2(30,20))
	gesture._gui_input(_touch(1, true, Vector2(90,20)))
	gesture._gui_input(_touch(2, true, Vector2(140,20)))
	drag.index = 1; drag.position = Vector2(130,20); gesture._gui_input(drag)
	_ok("orbit: pinch zoom works and third pointer is not captured", motion[1] < 1.0 and gesture.points.size() == 2 and not gesture.points.has(2))
	gesture._input(_touch(1, false, Vector2.ZERO, true))
	_ok("orbit: canceled pinch releases only its owner", gesture.points.size() == 1 and gesture.points.has(0))
	gesture.hide()
	_ok("orbit: hidden view releases every pointer", gesture.points.is_empty())
	gesture.queue_free()
	# simulated cutouts: every HUD button must stay inside the safe area at phone and tablet aspect ratios
	var hud_ok := true
	var hud_bad := []
	for case in [[Vector2(2400, 1080), Rect2(132, 0, 2136, 1080)], [Vector2(2400, 1080), Rect2(0, 60, 2400, 960)], [Vector2(1920, 1200), Rect2(0, 0, 1920, 1200)],
			[Vector2(1600, 1200), Rect2(40, 30, 1520, 1140)], [Vector2(2960, 1344), Rect2(148, 0, 2664, 1344)]]:
		var hud := HUD.new()
		hud.size = case[0]
		get_parent().ui.add_child(hud)
		hud.size = case[0]
		UITheme.safe_area_override = case[1]
		hud._layout()
		for n in hud.btn:
			var b: Control = hud.btn[n]
			if b.visible and not (case[1] as Rect2).grow(0.5).encloses(Rect2(b.position, b.size)):
				hud_ok = false
				hud_bad.append("%s %s in %s" % [n, str(Rect2(b.position, b.size)), str(case[1])])
		UITheme.safe_area_override = Rect2()
		hud.queue_free()
	_ok("UI: HUD buttons stay inside simulated cutouts at 20:9, 16:10, 4:3 and 2.2:1", hud_ok, str(hud_bad))
	var area := UITheme.scale_safe_area(Vector2(1600,740), Vector2(2400,1080), Rect2(120,0,2280,990))
	_ok("UI: safe area converts both axes independently", is_equal_approx(area.position.x, 80) and is_equal_approx(area.end.x,1600) and absf(area.end.y - 678.333333) < 0.01, str(area))
	await _frames(2)

func t_snapshot_transport() -> void:
	await _spawn("skylark")
	ac.freeze = true
	ac.place(Transform3D(Basis(), Vector3(0,70,0)))
	ac.in_throttle = 0.63; ac.brake = 0.8
	ac.panels[0]["cl"] = 0.42
	ac.wheels[0]["surface"] = 3
	var state := ac.snapshot()
	ac.in_throttle = 0.0; ac.brake = 0.0; ac.panels[0]["cl"] = -1.0; ac.wheels[0]["surface"] = 0
	ac.restore(state)
	_ok("snapshot: throttle, brake, aero state and wheel surface restore", is_equal_approx(ac.in_throttle,0.63) and is_equal_approx(ac.brake,0.8) and is_equal_approx(ac.panels[0]["cl"],0.42) and ac.wheels[0]["surface"] == 3)
	var tx := Transmitter.new(); tx.set_profile(Settings.TX_PRESETS["Gentle"])
	tx.process(0.7,-0.3,0.2,0.01)
	var saved_tx := tx.snapshot()
	var expected := tx.process(0.5,-0.2,0.1,0.01)
	tx.reset(); tx.restore(saved_tx)
	_ok("snapshot: transmitter smoothing resumes at historical state", tx.process(0.5,-0.2,0.1,0.01).is_equal_approx(expected))
	var rp := Replay.new(); holder.add_child(rp); rp.bind(ac, fx, field.npcs)
	for i in 7201:
		ac.global_position = Vector3(float(i) / 60.0, 70, 0)
		rp.record(float(i) / 60.0)
		if i == 600: rp.pin_crash(10.0)
	_ok("replay: two minutes of live aftermath retain original impact", rp.pinned.size() >= 1000 and rp.pinned.size() <= Replay.MAX_PINNED and float(rp.pinned[0]["t"]) <= 4.02 and float(rp.pinned.back()["t"]) >= 21.9 and rp.count == Replay.MAX_FRAMES)
	var original := ac.global_transform
	rp.start(4.0,120.0,10.0); rp.seek(0.25)
	_ok("replay: seek pauses an active session", rp.session_active and rp.paused and ac.replay_driven)
	rp.paused = false; rp._process(100.0)
	_ok("replay: natural end keeps a seekable session", rp.finished and rp.session_active)
	rp.seek(0.4)
	_ok("replay: end-to-seek resumes paused transport", rp.session_active and rp.paused and not rp.finished)
	rp.start(rp.t0, rp.t1, 10.0); rp.seek(0.9); rp.stop()
	_ok("replay: restart/seek/stop restores the original live state once", ac.global_transform.is_equal_approx(original) and is_equal_approx(ac.in_throttle,0.63) and not ac.replay_driven)
	rp.clear()
	var empty := true
	for f in rp.frames: empty = empty and f == null
	_ok("replay: clear releases ring and pinned frame references", empty and rp.pinned.is_empty() and rp.count == 0)
	rp.queue_free(); ac.freeze = false
	await _frames(2)
	_ok("altitude: flight above 60 m reports terrain AGL, not probe cap", ac.terrain_agl > 65 and ac.altitude_valid, str(ac.terrain_agl))

func t_camera_regression() -> void:
	var camera := CameraRig.new(); holder.add_child(camera)
	camera.target = ac
	camera.override_target = true
	camera.target_xf = Transform3D(Basis(),Vector3(0,70,0))
	camera.replay_aircraft_focus = Vector3(0,70,0)
	camera.replay_focus = Vector3(0,70,0)
	camera.shot_origin = Vector3(0,70,0)
	camera.shot_velocity = Vector3(10,0,0)
	camera.shot_clock = 1.0; camera.set_mode("cinematic")
	var position := camera._desired_pos()
	for i in 400: camera._desired_pos()
	_ok("camera: high-altitude cinematic does not pick a new shot every frame", camera.cine_picks == 1 and position.y > 40.0, "picks=%d position=%s" % [camera.cine_picks, position])
	camera.shot_clock = 4.0; camera._desired_pos()
	_ok("camera: shot advances at a deterministic cut boundary", camera.cine_picks == 2)
	camera.replay_aircraft_focus = Vector3(10,75,4)
	_ok("camera: replay uses recorded COM, not current damaged mass centre", camera._focus_point() == Vector3(10,75,4))
	var result := camera._avoid(Vector3(-80,5,0),Vector3(-80,-2,0))
	_ok("camera: endpoint stays above terrain", result.y >= field.ground_y(result) + 0.29, str(result))
	camera.queue_free(); await _frames(2)

func t_rotated_contact_coordinates() -> void:
	_ok("contact: head-on speed contains no false sliding", Aircraft.contact_tangent(Vector3(0,-10,0),Vector3.UP).length() < 0.00001)
	_ok("contact: glancing velocity retains only tangential component", Aircraft.contact_tangent(Vector3(3,-10,4),Vector3.UP).is_equal_approx(Vector3(3,0,4)))
	var floor_body := StaticBody3D.new(); floor_body.collision_layer = Game.L_WORLD
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(4,0.2,4); cs.shape = box
	floor_body.add_child(cs); holder.add_child(floor_body); floor_body.position = Vector3(1000,300,0)
	var probe := ContactProbe.new(); probe.gravity_scale = 0.0; probe.max_contacts_reported = 8; probe.contact_monitor = true
	probe.collision_layer = Game.L_AIRCRAFT; probe.collision_mask = Game.L_WORLD
	var pcs := CollisionShape3D.new(); var shape := BoxShape3D.new(); shape.size = Vector3(0.4,0.2,0.3); pcs.shape = shape
	probe.add_child(pcs); holder.add_child(probe)
	probe.global_transform = Transform3D(Basis(Vector3.BACK,PI/2),Vector3(1000,300.7,0)); probe.linear_velocity = Vector3(0,-2,0)
	await _frames(90)
	var n: Vector3 = probe.normals[0] if not probe.normals.is_empty() else Vector3.ZERO
	_ok("contact: Jolt reports world-space normal on a rotated body", not probe.normals.is_empty() and n.dot(Vector3.UP) > 0.95, str(n))
	probe.queue_free(); floor_body.queue_free(); await _frames(2)

func t_quality_roundtrip() -> void:
	var density := float(Settings.g("graphics","grass",1.0))
	Settings.s("graphics","grass",1.0)
	field.set_time_of_day("golden"); field.apply_quality("ultra")
	var first := _visible_grass_count()
	var glow := field.env.glow_enabled
	field.apply_quality("performance"); field.apply_quality("ultra")
	var last := _visible_grass_count()
	_ok("quality: Ultra survives Performance round trip without missing grass/glow", first == last and field.env.glow_enabled == glow and first > 0, "%d -> %d" % [first,last])
	Settings.s("graphics","grass",0.0); field.apply_quality("high")
	_ok("quality: zero grass density is respected live", _visible_grass_count() == 0)
	Settings.s("graphics","grass",density); field.apply_quality("high")
	await _frames(2)

func t_production_loop() -> void:
	if is_instance_valid(ac): ac.queue_free(); await _frames(2)
	var main := get_parent()
	main.field = field; main.fx = fx
	var fl := Flight.new(); holder.add_child(fl)
	main.flight = fl; main.state = "flight"
	fl.start("skylark", "free", field, fx, main.cam, main.ui)
	await _frames(5)
	fl.pause_game(); main._open_settings(); await get_tree().process_frame
	main._handle_back(); await get_tree().process_frame
	_ok("navigation: Back closes Settings without resuming paused flight", fl.state == Flight.S.PAUSED and get_tree().paused)
	main._handle_back(); await get_tree().process_frame
	_ok("navigation: following Back resumes the paused flight", fl.state == Flight.S.FLYING and not get_tree().paused)
	fl.modes.invalidate_for_rewind()
	_ok("challenge: rewind becomes practice with cleared objective progress", fl.modes.practice and not fl.modes.running and fl.modes.gate_idx == 0 and fl.modes.score == 0 and not fl.modes._save_ghost(1.0))
	var first_count := 0
	var valid := true
	var faces_ok := false
	var old_aftermath := float(Settings.g("gameplay","aftermath",4.0))
	Settings.s("gameplay","aftermath",12.0)
	for cycle in 20:
		fl.repair_and_fly()
		fl.aircraft.place(Transform3D(Basis(Vector3.UP,-PI*0.5) * Basis(Vector3.RIGHT,-1.2),Vector3(-60,4,-15)),26.0)
		for tick in 480:
			await get_tree().physics_frame
			if fl.state == Flight.S.AFTERMATH: break
		if fl.state != Flight.S.AFTERMATH:
			valid = false; print("Cycle did not reach aftermath: ",cycle); break
		await _frames(20)
		for cut in fl.aircraft.build.get("fractures", []):
			for node in cut["nodes"]: faces_ok = faces_ok or node.visible
		fl._start_killcam()
		fl.replay.seek(0.3); fl.replay.paused = false; fl.replay._process(100.0)
		valid = valid and fl.state == Flight.S.KILLCAM_END and fl.replay.session_active
		fl.replay.seek(0.5)
		valid = valid and fl.replay.paused
		fl.repair_and_fly()
		await _frames(4)
		valid = valid and fl.state == Flight.S.FLYING and not get_tree().paused and not fl.aircraft.crashed_flag and not fl.replay.session_active
		if cycle == 3: first_count = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var final_count := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	_ok("production: 20 real crash/aftermath/replay/end/seek/repair cycles", valid)
	_ok("production: new fracture interiors become visible on separated structures", faces_ok)
	_ok("production: full lifecycle object count remains bounded", valid and first_count > 0 and final_count - first_count < 100, "%d -> %d" % [first_count,final_count])
	var repaired := true
	for cut in fl.aircraft.build.get("fractures", []):
		for node in cut["nodes"]: repaired = repaired and not node.visible
	_ok("production: repair hides fracture faces again", repaired)
	Settings.s("gameplay","aftermath",old_aftermath)
	main.flight = null; main.state = "test"; fl.stop()
	await _frames(3)

func _visible_grass_count() -> int:
	var result := 0
	for node in field.grass_nodes:
		result += node.multimesh.visible_instance_count
	return result
