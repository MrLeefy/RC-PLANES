class_name AircraftStructure
extends RefCounted
## Opt-in structural proof. Local cage is anchored to the Jolt-owned
## fuselage; forces are one-way so the existing flight integrator stays intact.
## Four nodes per structural component form a tetrahedral deformation cage.

var solver: Object
var aircraft: Aircraft
var cages: Array = []
var beam_components := PackedInt32Array()
var elapsed := 0.0
var last_substeps := 0
var contact_count := 0
var panel_rest: Array = []
var panel_cages := PackedInt32Array()
const MAX_ACTIVE_DEBRIS := 6

static func available() -> bool:
	return ClassDB.class_exists("RCBeamSolver")

func setup(owner_aircraft: Aircraft) -> bool:
	if not available():
		return false
	aircraft = owner_aircraft
	solver = ClassDB.instantiate("RCBeamSolver")
	solver.configure(4, 8, 8, 0.12, 0.25)
	solver.reserve(100, 650)
	cages.resize(aircraft.comps.size())
	beam_components.clear()
	for ci in aircraft.comps.size():
		var comp: Dictionary = aircraft.comps[ci]
		var kind := String(comp["kind"])
		if ci != 0 and kind not in ["wing", "wingtip", "fuselage", "engine", "nacelle", "gear", "stab", "fin"]:
			continue
		var center: Vector3 = comp["center"]
		var half: Vector3 = (comp["size"] as Vector3).max(Vector3.ONE * 0.04) * 0.35
		var rest := PackedVector3Array([
			center + Vector3(-half.x, -half.y, -half.z),
			center + Vector3(half.x, -half.y, half.z),
			center + Vector3(-half.x, half.y, half.z),
			center + Vector3(half.x, half.y, -half.z),
		])
		var ids := PackedInt32Array()
		var node_mass := maxf(float(comp["mass"]) * 0.25, 0.005)
		for point in rest:
			ids.append(solver.add_node(point, node_mass, ci == 0))
		var rest_basis := Basis(rest[1] - rest[0], rest[2] - rest[0], rest[3] - rest[0])
		cages[ci] = {"nodes": ids, "rest": rest, "inverse": rest_basis.inverse(), "attachment": -1, "transform": Transform3D.IDENTITY}
		for a in 4:
			for b in range(a + 1, 4):
				_add_beam(ids[a], ids[b], kind, node_mass, 0, -1, a == 0)
	# Attachment groups are separate from internal spar/skin members. Breaking
	# a spar does not automatically delete every beam in an entire wing.
	for ci in range(1, cages.size()):
		if cages[ci] == null:
			continue
		var parent := int(aircraft.comps[ci]["parent"])
		while parent > 0 and cages[parent] == null:
			parent = int(aircraft.comps[parent]["parent"])
		parent = maxi(parent, 0)
		var node_mass := maxf(float(aircraft.comps[ci]["mass"]) * 0.25, 0.005)
		for a in cages[parent]["nodes"]:
			for b in cages[ci]["nodes"]:
				var index := _add_beam(a, b, String(aircraft.comps[ci]["kind"]), node_mass, ci + 1, ci, true)
				cages[ci]["attachment"] = index
	panel_rest = aircraft.panels.duplicate(true)
	for panel in aircraft.panels:
		var ci := int(panel["comp"])
		while ci > 0 and cages[ci] == null:
			ci = int(aircraft.comps[ci]["parent"])
		panel_cages.append(maxi(ci, 0))
		panel["structure_eff"] = 1.0
	return true

func _add_beam(a: int, b: int, kind: String, node_mass: float, group: int, ci: int, spar: bool) -> int:
	# Effective member stiffness is bounded for tiny RC node masses at 480 Hz.
	# These values are proof tuning seeds, not calibrated material constants.
	var yield_strain := 0.045
	var fracture := 0.40
	var flow := 7.0
	var plastic_cap := 0.30
	if kind in ["wing", "wingtip"] and spar:
		yield_strain = 0.018
		fracture = 0.12
		flow = 0.2
		plastic_cap = 0.012
	elif kind in ["engine", "nacelle"]: # firewall / motor mount
		yield_strain = 0.025
		fracture = 0.18
		flow = 1.0
		plastic_cap = 0.05
	elif kind == "gear":
		yield_strain = 0.035
		fracture = 0.48
		flow = 5.0
		plastic_cap = 0.25
	elif kind in ["fuselage", "stab", "fin"]:
		yield_strain = 0.025
		fracture = 0.20
		flow = 1.0
		plastic_cap = 0.05
	var index: int = solver.add_beam_custom(a, b, node_mass * 2400.0,
		node_mass * 12.0, yield_strain, yield_strain * 1.2,
		fracture, fracture * 1.2, flow, plastic_cap, group)
	if index >= 0:
		beam_components.append(ci)
	return index

func contact(world_position: Vector3, world_impulse: Vector3, body_transform: Transform3D) -> void:
	if aircraft.damage_mode != "physical" or aircraft.replay_driven or world_impulse.length_squared() < 1e-8:
		return
	var local_position := body_transform.affine_inverse() * world_position
	var local_impulse := body_transform.basis.transposed() * world_impulse
	solver.apply_radial_impulse(local_position, local_impulse, maxf(aircraft.span * 0.15, 0.15))
	solver.notify_impact(clampf(world_impulse.length() / maxf(aircraft.mass * 4.0, 0.1), 0.0, 1.0))
	contact_count += 1

func step(dt: float) -> void:
	if aircraft.replay_driven or aircraft.damage_mode != "physical":
		return
	last_substeps = solver.step_fast(dt)
	elapsed += dt
	for i in solver.get_break_event_count():
		var bi: int = solver.get_break_event(i)
		var ci := beam_components[bi]
		if ci < 1 or aircraft.comps[ci]["detached"]:
			continue
		var attachment: int = cages[ci]["attachment"]
		if solver.is_beam_broken(attachment) and _debris_count() + aircraft.detach_queue.size() < MAX_ACTIVE_DEBRIS:
			aircraft._request_detach(ci, {"sev": 6.0, "pos": aircraft.global_transform * aircraft.comps[ci]["center"], "cause": "rcbeam"})
	solver.clear_break_events()
	_update_deformation()
	_update_aero()

func _debris_count() -> int:
	var count := 0
	for rb in aircraft.debris_bodies:
		if rb != null and not rb.freeze:
			count += 1
	return count

func _update_deformation() -> void:
	for ci in range(1, cages.size()):
		if cages[ci] == null or aircraft.comps[ci]["detached"]:
			continue
		var cage: Dictionary = cages[ci]
		var ids: PackedInt32Array = cage["nodes"]
		var p0: Vector3 = solver.get_node_position(ids[0])
		var p1: Vector3 = solver.get_node_position(ids[1])
		var p2: Vector3 = solver.get_node_position(ids[2])
		var p3: Vector3 = solver.get_node_position(ids[3])
		var deformation: Basis = Basis(p1 - p0, p2 - p0, p3 - p0) * cage["inverse"]
		if not deformation.is_finite() or absf(deformation.determinant()) < 0.001:
			continue
		var transform := Transform3D(deformation, p0 - deformation * cage["rest"][0])
		cage["transform"] = transform

func is_released(ci: int) -> bool:
	while ci > 0:
		if cages[ci] != null and solver.is_beam_broken(cages[ci]["attachment"]):
			return true
		ci = int(aircraft.comps[ci]["parent"])
	return false

func _update_aero() -> void:
	for i in aircraft.panels.size():
		var ci := panel_cages[i]
		if ci == 0 or cages[ci] == null:
			continue
		var panel: Dictionary = aircraft.panels[i]
		var rest: Dictionary = panel_rest[i]
		var cage: Dictionary = cages[ci]
		var transform: Transform3D = cage["transform"]
		var deformation := transform.basis
		panel["pos"] = transform * (rest["pos"] as Vector3)
		panel["fwd"] = (deformation * (rest["fwd"] as Vector3)).normalized()
		panel["nrm"] = (deformation.inverse().transposed() * (rest["nrm"] as Vector3)).normalized()
		panel["span"] = (panel["fwd"] as Vector3).cross(panel["nrm"] as Vector3).normalized()
		var span := deformation * (rest["span"] as Vector3)
		var chord := deformation * (rest["fwd"] as Vector3)
		panel["area"] = float(rest["area"]) * clampf(span.cross(chord).length(), 0.1, 1.5)
		var released := is_released(ci)
		panel["structure_eff"] = 0.0 if released else 1.0
		# No lift or control authority remains on the parent after an attachment
		# fails, including when the debris budget keeps it from becoming a body.
		if released:
			panel["alive"] = false
			for control in panel["ctrls"]:
				aircraft.surfaces[int(control["surf"])]["dead"] = true
	for ei in aircraft.eng_defs.size():
		if is_released(int(aircraft.eng_defs[ei]["comp"])):
			aircraft.engines[ei].mount_ok = false

func reset_aero() -> void:
	for i in mini(panel_rest.size(), aircraft.panels.size()):
		for key in ["pos", "fwd", "nrm", "span", "area"]:
			aircraft.panels[i][key] = panel_rest[i][key]
		aircraft.panels[i]["structure_eff"] = 1.0

func deform_visuals(body_transform: Transform3D) -> void:
	if aircraft.replay_driven or aircraft.damage_mode != "physical":
		return
	for ci in range(1, cages.size()):
		if cages[ci] == null or aircraft.comps[ci]["detached"]:
			continue
		(aircraft.comps[ci]["visual"] as Node3D).global_transform = body_transform * cages[ci]["transform"] * aircraft.comps[ci].get("config_transform", Transform3D.IDENTITY)
