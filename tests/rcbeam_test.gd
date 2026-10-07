extends Node

var failures := 0
var checks := 0

func _ready() -> void:
	call_deferred("_run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func _run() -> void:
	if "--without-native" in OS.get_cmdline_user_args():
		check(not AircraftStructure.available(), "extension is absent for fallback test")
		for definition in AircraftDB.all():
			var plane := Aircraft.new()
			plane.setup(definition, {"rcbeam": true}, 2)
			add_child(plane)
			plane.freeze = true
			await get_tree().process_frame
			check(plane.structure == null and plane.mass > 0, "%s falls back safely without native library" % definition["id"])
			plane.queue_free()
			await get_tree().process_frame
		print("RCBEAM FALLBACK TEST checks=%d failures=%d" % [checks, failures])
		get_tree().quit(0 if failures == 0 else 1)
		return
	check(AircraftStructure.available(), "Godot 4.7 loads RCBeamSolver")
	if failures > 0:
		get_tree().quit(1)
		return
	var solver: Object = ClassDB.instantiate("RCBeamSolver")
	solver.configure(4, 10000, 8, 0.12, 0.25)
	solver.reserve(4, 4)
	check(solver.add_node(Vector3.ZERO, 1.0, true) == 0, "native pinned node")
	check(solver.add_node(Vector3.RIGHT, 1.0, false) == 1, "native free node")
	check(solver.add_beam_custom(0, 1, 0.0, 0.0, 0.01, 0.01, 1.0, 1.0, 20.0, 0.25, 3) == 0, "native custom beam")
	solver.apply_impulse(1, Vector3.RIGHT)
	solver.notify_impact(1.0)
	check(solver.step_fast(1.0 / 120.0) == 8, "impact substeps hard capped at eight")
	for i in 30:
		solver.step_fast(1.0 / 120.0)
	check(solver.get_beam_rest_length(0) > 1.01, "plastic rest length changes permanently")
	check(not solver.is_beam_broken(0), "yield does not require fracture")
	check(solver.step_fast(1.0) == 0, "reject unbounded frame duration")
	check(solver.get_node_position(-1) == Vector3.ZERO, "invalid node safe")

	var aircraft := Aircraft.new()
	aircraft.setup(AircraftDB.by_id("skylark"), {"rcbeam": true}, 2)
	add_child(aircraft)
	aircraft.freeze = true
	await get_tree().process_frame
	var proof: AircraftStructure = aircraft.structure
	check(proof != null, "Skylark opt-in creates structural graph")
	if proof == null:
		aircraft.free()
		get_tree().quit(1)
		return
	var nodes: int = proof.solver.get_node_count()
	var beams: int = proof.solver.get_beam_count()
	var force_before: Array = aircraft._aero(Vector3(0, 0, -12), Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, 1.0, false)
	check(nodes >= 45 and nodes <= 100 and beams <= 650, "mobile graph budget nodes=%d beams=%d" % [nodes, beams])
	for i in 1200:
		proof.step(1.0 / 120.0)
	var stable := true
	var wing := -1
	var gear := -1
	var nose := -1
	var tail := -1
	for ci in proof.cages.size():
		if proof.cages[ci] == null:
			continue
		for i in 4:
			var position: Vector3 = proof.solver.get_node_position(proof.cages[ci]["nodes"][i])
			stable = stable and position.distance_to(proof.cages[ci]["rest"][i]) < 0.00001
		var comp: Dictionary = aircraft.comps[ci]
		if comp["kind"] == "wing": wing = ci
		if comp["kind"] == "gear": gear = ci
		if comp["id"] == "nose": nose = ci
		if comp["id"] == "tail_boom": tail = ci
	check(stable, "ten seconds at rest has no drift or spontaneous breakage")
	var force_rest: Array = aircraft._aero(Vector3(0, 0, -12), Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, 1.0, false)
	check((force_before[0] as Vector3).distance_to(force_rest[0]) < 0.0001 and (force_before[1] as Vector3).distance_to(force_rest[1]) < 0.0001, "intact cage preserves original flight forces and torque")
	check(wing >= 0 and gear >= 0 and nose >= 0 and tail >= 0, "spar/firewall/gear/tail cages exist")
	# Coordinate conversion: equivalent contacts on a translated/rotated body
	# produce equivalent node positions in its local cage.
	var other := AircraftStructure.new()
	other.setup(aircraft)
	var local_point: Vector3 = proof.cages[wing]["rest"][0]
	var impulse := Vector3(0.0, 0.02, 0.0)
	var body := Transform3D(Basis(Vector3.UP, 0.7), Vector3(12, 8, -3))
	proof.contact(local_point, impulse, Transform3D.IDENTITY)
	other.contact(body * local_point, body.basis * impulse, body)
	proof.step(1.0 / 120.0)
	other.step(1.0 / 120.0)
	var equal := true
	for i in nodes:
		equal = equal and (proof.solver.get_node_position(i) as Vector3).distance_to(other.solver.get_node_position(i)) < 0.00001
	check(equal, "world contact impulse converts to aircraft-local coordinates")
	var force_bent: Array = aircraft._aero(Vector3(0, 0, -12), Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, 1.0, false)
	check((force_before[0] as Vector3).distance_to(force_bent[0]) > 0.0001, "wing deformation changes aerodynamic force")
	check((force_before[1] as Vector3).distance_to(force_bent[1]) > 0.0001, "asymmetric wing deformation changes flight torque")
	check(proof.last_substeps == 4 and proof.contact_count == 1, "small contact retains normal substep budget")
	aircraft.update_visuals(Transform3D.IDENTITY, 0.0)
	var visual: Node3D = aircraft.comps[wing]["visual"]
	check(not visual.global_transform.is_equal_approx(Transform3D.IDENTITY), "cage deforms existing baked visual")
	var bent_transform: Transform3D = proof.cages[wing]["transform"]
	aircraft.detach(wing)
	aircraft.update_visuals(Transform3D.IDENTITY, 0.0)
	var debris: RigidBody3D = aircraft.debris_bodies[wing]
	var expected := debris.global_transform * Transform3D(Basis(), -aircraft.comps[wing]["center"]) * bent_transform
	check(visual.global_transform.is_equal_approx(expected), "detached wing retains its bent shape")
	# Fresh graph for each destructive case, preserving isolation.
	for ci in [wing, nose, gear, tail]:
		aircraft.repair_all()
		proof = aircraft.structure
		local_point = proof.cages[ci]["rest"][0]
		proof.contact(local_point, Vector3(0, 10, 0), Transform3D.IDENTITY)
		for i in 60:
			proof.step(1.0 / 120.0)
		check(proof.solver.is_beam_broken(proof.cages[ci]["attachment"]), "attachment fractures: %s" % aircraft.comps[ci]["id"])
		check(aircraft.detach_queue.size() <= AircraftStructure.MAX_ACTIVE_DEBRIS, "bounded structural detach queue")
		if ci == wing:
			var lost_lift := false
			for pi in aircraft.panels.size():
				if proof.panel_cages[pi] == ci:
					lost_lift = lost_lift or not aircraft.panels[pi]["alive"]
			check(lost_lift, "broken wing attachment removes parent lift")
			var descendants_released := true
			for pi in aircraft.panels.size():
				if int(aircraft.panels[pi]["comp"]) in aircraft._descendants(wing):
					descendants_released = descendants_released and not aircraft.panels[pi]["alive"]
			check(descendants_released, "released wing descendants lose lift before debris activation")
		aircraft.detach_queue.clear()
	aircraft.repair_all()
	proof = aircraft.structure
	var engine_ci: int = aircraft.eng_defs[0]["comp"]
	while engine_ci > 0 and proof.cages[engine_ci] == null:
		engine_ci = int(aircraft.comps[engine_ci]["parent"])
	proof.contact(proof.cages[engine_ci]["rest"][0], Vector3(0, 10, 0), Transform3D.IDENTITY)
	for i in 60:
		proof.step(1.0 / 120.0)
	check(proof.is_released(engine_ci) and not aircraft.engines[0].mount_ok, "released firewall disables thrust before debris activation")
	aircraft.detach_queue.clear()
	aircraft.repair_all()
	check(aircraft.structure.solver.get_break_event_count() == 0, "repair rebuilds pristine structure")
	aircraft.structure = null
	aircraft.free()
	await get_tree().process_frame
	# Exercise the actual Aircraft._contacts callback under Jolt, not only the
	# direct bridge API. A large floor catches every detached assembly.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = Game.L_WORLD
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(50, 0.1, 50)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	add_child(floor_body)
	var drop := Aircraft.new()
	drop.setup(AircraftDB.by_id("skylark"), {"rcbeam": true}, 2)
	add_child(drop)
	drop.position = Vector3(0, 2, 0)
	drop.contact_grace = 0
	for i in 360:
		await get_tree().physics_frame
	check(drop.structure.contact_count > 0, "Jolt drop delivers real contact impulses to RCBeam")
	check(drop.structure._debris_count() <= AircraftStructure.MAX_ACTIVE_DEBRIS, "live crash respects six-body debris budget")
	drop.queue_free()
	floor_body.queue_free()
	await get_tree().process_frame
	var fallback := Aircraft.new()
	fallback.setup(AircraftDB.by_id("skylark"), {}, 0, true)
	check(fallback.structure == null, "legacy fallback has no structural work by default")
	check(not fallback.enable_structure_proof() or AircraftStructure.available(), "dynamic native class avoids mandatory extension dependency")
	fallback.free()
	var configured := Aircraft.new()
	configured.setup(AircraftDB.by_id("valor"), {"cg": -0.06}, 2)
	add_child(configured)
	configured.freeze = true
	await get_tree().process_frame # Deferred debris root must enter the tree.
	var shifted_gear := -1
	for ci in configured.comps.size():
		if configured.comps[ci].has("config_transform"):
			shifted_gear = ci
			break
	check(shifted_gear >= 0, "Workshop CG configuration translates premade gear")
	if shifted_gear >= 0:
		var replay := Replay.new()
		replay.bind(configured, null, [])
		replay.record(0.0)
		configured.apply_replay(replay.frames[0], replay.frames[0], 0.0, 0.0)
		var gear_visual: Node3D = configured.comps[shifted_gear]["visual"]
		var gear_offset: Transform3D = configured.comps[shifted_gear]["config_transform"]
		check(gear_visual.transform.is_equal_approx(gear_offset), "attached replay preserves configured gear position")
		configured.detach(shifted_gear)
		configured.update_visuals(Transform3D.IDENTITY, 0.0)
		var gear_body: RigidBody3D = configured.debris_bodies[shifted_gear]
		var gear_expected := gear_body.global_transform * Transform3D(Basis(), -configured.comps[shifted_gear]["center"]) * gear_offset
		check(gear_visual.global_transform.is_equal_approx(gear_expected), "detached gear preserves Workshop position")
		replay.record(1.0)
		configured.apply_replay(replay.frames[1], replay.frames[1], 0.0, 0.0)
		check(gear_visual.global_transform.is_equal_approx(gear_expected), "detached replay preserves configured gear position")
		replay.free()
	configured.free()
	await get_tree().process_frame
	var fleet_ok := true
	var max_nodes := 0
	var max_beams := 0
	for definition in AircraftDB.all():
		var plane := Aircraft.new()
		plane.setup(definition, {}, 2, true)
		fleet_ok = fleet_ok and plane.enable_structure_proof()
		var rig: AircraftStructure = plane.structure
		max_nodes = maxi(max_nodes, rig.solver.get_node_count())
		max_beams = maxi(max_beams, rig.solver.get_beam_count())
		for i in 120:
			rig.step(1.0 / 120.0)
		for bi in rig.solver.get_beam_count():
			fleet_ok = fleet_ok and not rig.solver.is_beam_broken(bi)
		plane.free()
	check(fleet_ok and max_nodes <= 150 and max_beams <= 650, "all 16 premade models accept stable cages (max %d nodes/%d beams)" % [max_nodes, max_beams])
	print("RCBEAM GODOT TEST checks=%d failures=%d" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
