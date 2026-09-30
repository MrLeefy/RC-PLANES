class_name Aircraft
extends RigidBody3D
## RC Park flight model: rigid body + per-panel aerodynamics + propulsion +
## raycast landing gear + impulse-driven progressive structural damage.
##
## Nothing here clamps attitude or rotation rates. Stalls, spins, snap rolls,
## knife-edge and hovering all emerge from the panel aerodynamics.

signal crashed(info: Dictionary)
signal component_broken(comp_id: String, info: Dictionary)
signal touchdown(info: Dictionary)
signal message(text: String)

const RHO := 1.225
const G := 9.81

var def: Dictionary
var cfg: Dictionary
var build: Dictionary
var comps: Array = []
var panels: Array = []
var surfaces: Array = []
var eng_defs: Array = []
var engines: Array = []   # Propulsion
var wheels: Array = []
var body_drag: Dictionary = {}
var visual_root: Node3D
var detail := 2
var display_only := false
var ref_area := 0.3
var span := 1.0
var length_m := 1.0
var main_ar := 6.0
var mac_c := 0.2

# controls (inputs are -1..1, throttle 0..1)
var in_roll := 0.0
var in_pitch := 0.0
var in_yaw := 0.0
var in_throttle := 0.0
var flap_cmd := 0.0
var flap_pos := 0.0
var gear_down := true
var gear_pos := 1.0      # 1 = down, 0 = up
var brake := 0.0
var assist := "sport"
var damage_mode := "physical"
var rates_scale := 1.0
var ch_cmd = [0.0, 0.0, 0.0, 0.0]
var servo_speed := 420.0
var max_defl = [0.35, 0.35, 0.4, 0.6]
var controls_enabled := true

# battery / fuel
var bat_cells := 4
var bat_cap := 3.2
var bat_soc := 1.0
var bat_v := 16.8
var bat_r := 0.02
var bat_lvc := 1.0
var fuel_kg := 0.0
var fuel_max := 0.0
var total_current := 0.0

# state
var com_local := Vector3.ZERO
var agl := 99.0  # near-surface probe, used for ground effect
var terrain_agl := 0.0
var altitude_valid := false
var last_contact_speed := 0.0
var airspeed := 0.0
var aoa := 0.0
var beta := 0.0
var ground_speed := 0.0
var on_ground := false
var wheels_touching := 0
var airborne_time := 0.0
var ground_time := 0.0
var crashed_flag := false
var sim_t := 0.0
var wing_cl := 0.0
var g_load := 1.0
var last_vel := Vector3.ZERO
var foliage: Array = []
var foliage_sensor: Area3D

# damage bookkeeping
var shape_nodes: Array = []  # CollisionShape3D
var detach_queue: Array = []
var pending_mass_update := false
var debris_root: Node3D
var debris_bodies: Array = []  # per comp: RigidBody3D or null
var recent_breaks: Array = []
var impact_log: Array = []
var max_impact := 0.0
var scrape_level := 0.0
var last_impact_sfx := 0.0

# visuals / interpolation
var prev_xf := Transform3D()
var curr_xf := Transform3D()
var vis_xf := Transform3D()
var replay_driven := false
var replay_rate := 0.0
var replay_time := 0.0
var replay_owners := PackedInt32Array()
var prop_angle: Array = []
var wheel_spin_angle: Array = []

var _space_rid: RID
var _ray_params: PhysicsRayQueryParameters3D

# ================================================================ setup
func setup(definition: Dictionary, config: Dictionary, detail_level := 2, for_display := false) -> void:
	def = definition
	cfg = config
	detail = detail_level
	display_only = for_display
	name = String(def["id"])
	var b := AircraftBuilder.new()
	build = b.build(def, cfg, detail)
	comps = build["comps"]
	panels = build["panels"]
	surfaces = build["surfaces"]
	eng_defs = build["engines"]
	wheels = build["wheels"]
	body_drag = b.body_drag
	span = float(build["span"])
	length_m = float(build["length"])
	mac_c = float(build["mac"]["c"])
	ref_area = float(build["mac"]["area"])
	main_ar = span * span / maxf(ref_area, 0.01)
	servo_speed = float(def["servo_speed"])
	var r: Dictionary = def["rates"]
	var throws = 1.0 if String(cfg.get("throws", "high")) == "high" else 0.7
	max_defl = [deg_to_rad(float(r["ail"])) * throws, deg_to_rad(float(r["elev"])) * throws, deg_to_rad(float(r["rud"])) * throws, deg_to_rad(float(r["flap"]))]
	visual_root = build["root"]
	visual_root.top_level = true
	add_child(visual_root)
	for c in comps:
		c["hp"] = 1.0
		c["detached"] = false
		c["debris"] = -1
		c["dmg_vis"] = 0.0
		c["dirt"] = 0.0
		c["alive_shapes"] = []
		c["children"] = []
	for i in comps.size():
		var p := int(comps[i]["parent"])
		if p >= 0:
			(comps[p]["children"] as Array).append(i)
	for s in surfaces:
		s["health"] = 1.0
		s["dead"] = false
	for w in wheels:
		w["comp_now"] = 0.0
		w["prev_comp"] = 0.0
		w["spin_rate"] = 0.0
		w["steer"] = 0.0
		w["hp"] = 1.0
		w["bent"] = 0.0
		w["alive"] = true
		w["contact"] = false
		w["surface"] = 0
		w["load_now"] = 0.0
		w["was_contact"] = false
	for e in eng_defs:
		var pr := Propulsion.new()
		pr.setup(e)
		engines.append(pr)
		prop_angle.append(0.0)
	for w in wheels:
		wheel_spin_angle.append(0.0)
	_setup_power()
	_compute_wash()
	_build_collision()
	# physics body config
	collision_layer = Game.L_AIRCRAFT
	collision_mask = Game.L_WORLD | Game.L_NPC | Game.L_DEBRIS | Game.L_GATE
	continuous_cd = true
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 16
	custom_integrator = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	var pm := PhysicsMaterial.new()
	pm.friction = 0.55
	pm.bounce = 0.08
	physics_material_override = pm
	recompute_mass()
	has_htail = not (def["htail"] as Dictionary).is_empty()
	compute_factory_trim()
	gear_down = true
	gear_pos = 1.0
	if display_only:
		freeze = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		contact_monitor = false
		continuous_cd = false
	else:
		_build_debris_pool()
		_build_foliage_sensor()
	_ray_params = PhysicsRayQueryParameters3D.new()
	_ray_params.collision_mask = Game.L_WORLD | Game.L_NPC
	_ray_params.exclude = [get_rid()]
	_ray_params.hit_from_inside = false

func _setup_power() -> void:
	var t := String(def["engines"][0]["type"])
	if t in ["electric", "edf"]:
		var bats: Array = def["batteries"]
		if bats.is_empty():
			bats = [{"name": "6S 5000", "cells": 6, "cap": 5.0, "mass": 0.7}]
		var b: Dictionary = bats[clampi(int(cfg.get("battery", 0)), 0, bats.size() - 1)]
		bat_cells = int(b["cells"])
		bat_cap = float(b["cap"])
		bat_r = 0.0042 * bat_cells * clampf(3.2 / bat_cap, 0.3, 2.0)
		bat_soc = 1.0
	else:
		fuel_max = float(def["tank"]) * (0.74 if t == "gas2" else 0.8)
		fuel_kg = fuel_max * clampf(float(cfg.get("fuel", 1.0)), 0.05, 1.0)

func _compute_wash() -> void:
	for p in panels:
		p["wash"] = []
		var pos: Vector3 = p["pos"]
		var ext := float(p["area"]) / maxf(float(p["chord"]), 0.01) * 0.5
		var sd: Vector3 = p["span"]
		for ei in eng_defs.size():
			var e: Dictionary = eng_defs[ei]
			if not String(e["type"]) in ["electric", "glow2", "glow4", "gas2"]:
				continue
			var ep: Vector3 = e["pos"]
			var R := float(e["D"]) * 0.5
			if pos.z < ep.z:
				continue
			var a := pos - sd * ext
			var b := pos + sd * ext
			var frac := 0.0
			if absf(sd.x) > 0.6:
				# horizontal-ish surface: overlap in x, height check
				var lo := minf(a.x, b.x)
				var hi := maxf(a.x, b.x)
				var ov := maxf(0.0, minf(hi, ep.x + R * 1.1) - maxf(lo, ep.x - R * 1.1))
				if absf(pos.y - ep.y) < R * 1.4:
					frac = ov / maxf(hi - lo, 1e-3)
			elif absf(sd.y) > 0.6:
				var lo2 := minf(a.y, b.y)
				var hi2 := maxf(a.y, b.y)
				var ov2 := maxf(0.0, minf(hi2, ep.y + R * 1.1) - maxf(lo2, ep.y - R * 1.1))
				if absf(pos.x - ep.x) < R * 1.2:
					frac = ov2 / maxf(hi2 - lo2, 1e-3)
			if frac > 0.02:
				(p["wash"] as Array).append([ei, clampf(frac, 0.0, 1.0)])

func _make_shape(s: Dictionary) -> Shape3D:
	match String(s["type"]):
		"box":
			var b := BoxShape3D.new()
			b.size = s["size"]
			return b
		"sphere":
			var sp := SphereShape3D.new()
			sp.radius = float(s["r"])
			return sp
		"convex":
			var cv := ConvexPolygonShape3D.new()
			cv.points = s["points"]
			return cv
		"cyl":
			var cy := CylinderShape3D.new()
			cy.radius = float(s["r"])
			cy.height = float(s["h"])
			return cy
	return BoxShape3D.new()

func _build_collision() -> void:
	for ci in comps.size():
		var c: Dictionary = comps[ci]
		var res = []
		for s in c["shapes"]:
			var shape := _make_shape(s)
			var cs := CollisionShape3D.new()
			cs.shape = shape
			cs.transform = s["xf"]
			cs.set_meta("ci", ci)
			cs.set_meta("wheel", bool(s.get("wheel", false)))
			add_child(cs)
			shape_nodes.append(cs)
			res.append({"node": cs, "shape": shape, "xf": s["xf"]})
		c["col"] = res

func _build_debris_pool() -> void:
	# One pre-built rigid body per detachable component, containing the shapes of the
	# component AND all of its descendants (descendant shapes toggled at detach time).
	debris_root = Node3D.new()
	debris_root.name = "Debris_" + name
	debris_bodies.resize(comps.size())
	for ci in comps.size():
		debris_bodies[ci] = null
		if ci == 0:
			continue
		var c: Dictionary = comps[ci]
		var rb := RigidBody3D.new()
		rb.name = "db_" + String(c["id"])
		rb.freeze = true
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		rb.collision_layer = 0
		rb.collision_mask = 0
		rb.continuous_cd = false
		rb.can_sleep = true
		rb.contact_monitor = true
		rb.max_contacts_reported = 4
		rb.linear_damp = 0.05
		rb.angular_damp = 0.4
		var pm := PhysicsMaterial.new()
		pm.friction = 0.7
		pm.bounce = 0.18
		rb.physics_material_override = pm
		rb.set_script(preload("res://scripts/aircraft/debris_body.gd"))
		var center: Vector3 = c["center"]
		var members = [ci]
		members.append_array(_descendants(ci))
		var shape_map := {}
		for m in members:
			var lst = []
			for s in comps[m]["col"]:
				var cs := CollisionShape3D.new()
				cs.shape = s["shape"]
				cs.transform = Transform3D(Basis(), -center) * (s["xf"] as Transform3D)
				cs.disabled = true
				rb.add_child(cs)
				lst.append(cs)
			shape_map[m] = lst
		rb.set_meta("shape_map", shape_map)
		rb.set_meta("ci", ci)
		rb.set_meta("members", [])
		rb.set("aircraft", self)
		debris_root.add_child(rb)
		debris_bodies[ci] = rb
	# attach to the scene when we enter the tree
	call_deferred("_attach_debris_root")

func _attach_debris_root() -> void:
	if debris_root and not debris_root.is_inside_tree() and is_inside_tree():
		get_parent().add_child(debris_root)
		debris_root.process_mode = Node.PROCESS_MODE_PAUSABLE

func _build_foliage_sensor() -> void:
	foliage_sensor = Area3D.new()
	foliage_sensor.name = "FoliageSensor"
	foliage_sensor.collision_layer = 0
	foliage_sensor.collision_mask = Game.L_FOLIAGE
	foliage_sensor.monitorable = false
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(span * 0.9, maxf(span * 0.15, 0.15), length_m * 0.9)
	cs.shape = bs
	cs.position = Vector3(0, 0, length_m * 0.45)
	foliage_sensor.add_child(cs)
	add_child(foliage_sensor)

func _descendants(ci: int) -> Array:
	var out = []
	for ch in comps[ci]["children"]:
		out.append(ch)
		out.append_array(_descendants(ch))
	return out

func _exit_tree() -> void:
	if debris_root and is_instance_valid(debris_root):
		debris_root.queue_free()

# ================================================================ mass properties
func recompute_mass() -> void:
	var m := 0.0
	var mc := Vector3.ZERO
	var pts = []
	for c in comps:
		if c["detached"]:
			continue
		for pm in c["point_masses"]:
			var mm := float(pm["m"])
			if pm.get("payload", false) and fuel_max > 0.0:
				mm = fuel_kg
			pts.append([pm["pos"], mm, pm["size"]])
			m += mm
			mc += (pm["pos"] as Vector3) * mm
	m = maxf(m, 0.05)
	com_local = mc / m
	var I := Vector3.ZERO
	for p in pts:
		var r: Vector3 = (p[0] as Vector3) - com_local
		var mm2: float = p[1]
		var sz: Vector3 = p[2]
		I.x += mm2 * (r.y * r.y + r.z * r.z) + mm2 * (sz.y * sz.y + sz.z * sz.z) / 12.0
		I.y += mm2 * (r.x * r.x + r.z * r.z) + mm2 * (sz.x * sz.x + sz.z * sz.z) / 12.0
		I.z += mm2 * (r.x * r.x + r.y * r.y) + mm2 * (sz.x * sz.x + sz.y * sz.y) / 12.0
	mass = m
	center_of_mass = com_local
	inertia = I.max(Vector3(1e-4, 1e-4, 1e-4))

# ================================================================ controls
func set_inputs(roll: float, pitch: float, yaw: float, throttle: float) -> void:
	in_roll = clampf(roll, -1.0, 1.0)
	in_pitch = clampf(pitch, -1.0, 1.0)
	in_yaw = clampf(yaw, -1.0, 1.0)
	in_throttle = clampf(throttle, 0.0, 1.0)

func cycle_flaps() -> float:
	if max_defl[3] <= 0.001:
		return 0.0
	flap_cmd = 0.5 if flap_cmd < 0.25 else (1.0 if flap_cmd < 0.75 else 0.0)
	return flap_cmd

func has_flaps() -> bool:
	for s in surfaces:
		for m in s["mix"]:
			if int(m[0]) == 3:
				return true
	return false

func has_retracts() -> bool:
	return bool(def["gear"]["retract"])

func toggle_gear() -> void:
	if has_retracts():
		gear_down = not gear_down

func engine_toggle() -> String:
	var msg := ""
	for e in engines:
		if e.mount_ok:
			msg = e.start_request(in_throttle)
	message.emit(msg)
	return msg

func engines_running() -> bool:
	for e in engines:
		if e.running or e.starting > 0.0:
			return true
	return false

func kill_engines() -> void:
	for e in engines:
		e.kill()

func is_electric() -> bool:
	return String(def["engines"][0]["type"]) in ["electric", "edf"]

# ================================================================ physics
func _physics_process(delta: float) -> void:
	if display_only:
		return
	prev_xf = curr_xf
	curr_xf = global_transform
	if not detach_queue.is_empty():
		_process_detach_queue()
	if pending_mass_update:
		pending_mass_update = false
		recompute_mass()
	# fuel mass changes the CG slowly
	if fuel_max > 0.0 and Engine.get_physics_frames() % 60 == 0:
		recompute_mass()
	# gear retract animation
	var target := 1.0 if gear_down else 0.0
	gear_pos = move_toward(gear_pos, target, delta / 2.2)
	flap_pos = move_toward(flap_pos, flap_cmd, delta / 1.2)
	# foliage list refresh
	if foliage_sensor and Engine.get_physics_frames() % 4 == 0:
		foliage = foliage_sensor.get_overlapping_areas()
	# forget old breaks
	while recent_breaks.size() > 0 and sim_t - float(recent_breaks[0]) > 0.6:
		recent_breaks.pop_front()

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if display_only:
		return
	var dt := state.step
	sim_t += dt
	var xf := state.transform
	var B := xf.basis
	var Bt := B.transposed()
	var v_w := state.linear_velocity
	var w_w := state.angular_velocity
	var com_w := xf.origin + B * com_local
	var v_l := Bt * v_w
	var w_l := Bt * w_w
	var wind_w := Game.wind_at(com_w)
	var wind_l := Bt * wind_w
	# spanwise wind variation -> turbulence rolls the aircraft
	var wind_tip_l := Vector3.ZERO
	if Game.wind:
		var tipR := Game.wind_at(com_w + B.x * span * 0.5)
		var tipL := Game.wind_at(com_w - B.x * span * 0.5)
		wind_tip_l = Bt * (tipR - tipL) / maxf(span, 0.1)
	var air_l := v_l - wind_l
	airspeed = air_l.length()
	ground_speed = Vector2(v_w.x, v_w.z).length()
	if airspeed > 0.5:
		aoa = atan2(-air_l.y, -air_l.z)
		beta = atan2(air_l.x, -air_l.z)
	var acc := (v_w - last_vel) / maxf(dt, 1e-4)
	last_vel = v_w
	g_load = lerpf(g_load, (Bt * (acc + Vector3(0, G, 0))).y / G, 0.1)
	# ---- ground height (single ray) ----
	var space := state.get_space_state()
	_ray_params.from = com_w
	_ray_params.to = com_w + Vector3(0, -60.0, 0)
	var gh := space.intersect_ray(_ray_params)
	agl = (com_w.y - (gh["position"] as Vector3).y) if not gh.is_empty() else 60.0
	# Telemetry is terrain AGL, not a capped ground-effect/support probe.
	altitude_valid = is_instance_valid(Game.field) and absf(com_w.x) <= Field.HALF and absf(com_w.z) <= Field.HALF
	if altitude_valid:
		terrain_agl = maxf(0.0, com_w.y - Game.field.ground_y(com_w))
	else:
		terrain_agl = 0.0
	# ---- control mixing & servos ----
	_mix_controls(dt, B, w_l, air_l)
	var F := Vector3.ZERO
	var T := Vector3.ZERO
	# ---- propulsion ----
	var throttle := in_throttle if controls_enabled else 0.0
	var fuel_ok := fuel_max <= 0.0 or fuel_kg > 0.0005
	var bat := _battery_state()
	total_current = 0.0
	for ei in engines.size():
		var e: Propulsion = engines[ei]
		var ed: Dictionary = eng_defs[ei]
		var alive = not comps[int(ed["comp"])]["detached"]
		if int(ed["prop_comp"]) >= 0 and comps[int(ed["prop_comp"])]["detached"]:
			e.health = 0.0
		if not alive:
			e.mount_ok = false
		var r_e: Vector3 = e.pos - com_local
		var v_e := air_l + w_l.cross(r_e)
		var v_ax := v_e.dot(e.dir)
		e.step(dt, throttle, v_ax, bat, fuel_ok)
		total_current += e.current
		e.strike_torque = maxf(e.strike_torque - dt * 20.0, 0.0)
		if not alive:
			continue
		var fdir: Vector3 = e.dir
		var thrust_pt := r_e
		if e.is_prop():
			# P-factor: thrust centre shifts toward the descending blade at angle of attack / sideslip
			var a_p := atan2(-v_e.y, maxf(v_ax, 1.0))
			var b_p := atan2(v_e.x, maxf(v_ax, 1.0))
			var R := e.D * 0.5
			thrust_pt += Vector3(e.spin * 0.25 * R * sin(clampf(a_p, -1.0, 1.0)), -e.spin * 0.25 * R * sin(clampf(b_p, -1.0, 1.0)), 0.0)
			# torque reaction (roll) + gyroscopic precession
			T += -fdir * e.spin * e.torque
			var H := fdir * e.spin * e.omega * e.i_rot
			T += -w_l.cross(H)
			# vibration from damaged prop
			if e.health < 0.95 and e.omega > 50.0:
				var vib := (1.0 - e.health) * e.omega * e.omega * e.i_rot * 0.02
				var ph := sim_t * e.omega
				F += Vector3(cos(ph), sin(ph), 0.0) * vib
		F += fdir * e.thrust
		T += thrust_pt.cross(fdir * e.thrust)
	_update_battery(dt)
	if fuel_max > 0.0:
		for e in engines:
			fuel_kg = maxf(fuel_kg - e.fuel_burn_rate() * dt, 0.0)
	# ---- aerodynamics ----
	var ge_phi := 1.0
	if agl < span:
		var hb := maxf(agl, 0.02) / maxf(span, 0.1)
		ge_phi = (16.0 * hb) * (16.0 * hb) / (1.0 + (16.0 * hb) * (16.0 * hb))
	var aero := _aero(v_l, w_l, wind_l, wind_tip_l, ge_phi, true)
	F += aero[0]
	T += aero[1]
	# ---- fuselage & gear parasitic drag ----
	var rb: Vector3 = (body_drag["pos"] as Vector3) - com_local
	var vb := v_l + w_l.cross(rb) - wind_l
	var fd := Vector3(
		-0.5 * RHO * float(body_drag["side_cda"]) * vb.x * absf(vb.x),
		-0.5 * RHO * float(body_drag["top_cda"]) * vb.y * absf(vb.y),
		-0.5 * RHO * float(body_drag["front_cda"]) * vb.z * absf(vb.z))
	# gear drag fades with retraction
	fd += -0.5 * RHO * float(body_drag["gear_cda"]) * (gear_pos if has_retracts() else 1.0) * vb * vb.length()
	F += fd
	T += rb.cross(fd)
	# rotational damping of the body shape itself (fuselage cross-flow) - small
	T += -w_l * w_l.length() * 0.5 * RHO * float(body_drag["side_cda"]) * length_m * length_m * 0.004
	# ---- foliage (bush/canopy volumes) ----
	if not foliage.is_empty():
		_foliage_forces(dt, com_w, v_w, B, Bt, F, T)
		F += _fol_F
		T += _fol_T
	# ---- apply aero/propulsion in world space ----
	state.apply_central_force(B * F)
	state.apply_torque(B * T)
	# ---- landing gear (world space) ----
	_gear(state, dt, xf, com_w, v_w, w_w, space)
	# ---- contacts -> damage ----
	_contacts(state)
	on_ground = wheels_touching > 0 or _body_ground_contact
	if on_ground:
		ground_time += dt
		airborne_time = 0.0
	else:
		airborne_time += dt
		ground_time = 0.0

var _fol_F := Vector3.ZERO
var _fol_T := Vector3.ZERO

var _outer_foliage: Array = []

func _foliage_forces(dt: float, com_w: Vector3, v_w: Vector3, _B: Basis, Bt: Basis, _F: Vector3, _T: Vector3) -> void:
	_fol_F = Vector3.ZERO
	_fol_T = Vector3.ZERO
	var spd := v_w.length()
	for a in foliage:
		if is_instance_valid(a):
			_apply_canopy(dt, com_w, v_w, Bt, spd, a.get_meta("center", a.global_position),
				float(a.get_meta("radius", 2.0)), float(a.get_meta("density", 0.5)))
	if is_instance_valid(Game.field):
		Game.field.outer_canopies.query(com_w, span * 0.5, _outer_foliage)
		for crown in _outer_foliage:
			_apply_canopy(dt, com_w, v_w, Bt, spd, crown["center"], crown["radius"], crown["density"])
	# Overlapping crowns must not reverse velocity in one explicit physics step.
	_fol_F = _fol_F.limit_length(mass * maxf(spd, 1.0) * 0.7 / maxf(dt, 0.001))

func _apply_canopy(dt: float, com_w: Vector3, v_w: Vector3, Bt: Basis, spd: float, cen: Vector3, rad: float, dens: float) -> void:
	var pen := clampf((rad + span * 0.5 - com_w.distance_to(cen)) / maxf(span, 0.3), 0.0, 1.0)
	if pen <= 0.0:
		return
	var cda := ref_area * 2.8 * dens * pen
	var fdw := -0.5 * RHO * cda * v_w * spd * 4.0
	fdw += -v_w * mass * 2.5 * dens * pen
	if spd < 2.5:
		fdw += Vector3(0, mass * G * 0.85 * dens * pen, 0)
	_fol_F += Bt * fdw
	var jit := Vector3(Game.rng.randf_range(-1, 1), Game.rng.randf_range(-1, 1), Game.rng.randf_range(-1, 1))
	_fol_T += jit * mass * spd * 0.02 * dens * pen * span
	if spd > 7.0 and damage_mode != "off":
		var hits := int(spd * dt * dens * 3.0 + Game.rng.randf())
		for h in hits:
			var ci := _random_exposed_comp()
			if ci >= 0:
				_damage(ci, spd * 0.55 * dens, com_w, Vector3.UP, "foliage")
		if Game.fx and Game.rng.randf() < dt * 8.0:
			Game.fx.leaves(com_w, v_w * 0.3)

func _random_exposed_comp() -> int:
	# Reservoir sampling: uniform selection, no per-hit candidate Array allocation.
	var chosen := -1
	var count := 0
	for i in comps.size():
		var k := String(comps[i]["kind"])
		if not comps[i]["detached"] and k in ["wingtip", "control", "prop", "fin", "stab", "wing"]:
			count += 1
			if Game.rng.randi_range(1, count) == 1:
				chosen = i
	return chosen

## Per-panel aerodynamics (body frame). Returns [force, torque about CG].
func _aero(v_l: Vector3, w_l: Vector3, wind_l: Vector3, wind_tip_l: Vector3, ge_phi: float, update_state: bool) -> Array:
	var F := Vector3.ZERO
	var T := Vector3.ZERO
	var cl_sum := 0.0
	var cl_area := 0.0
	var ge_on := ge_phi < 0.999
	# downwash from last step's wing lift
	var downwash := clampf(2.0 * wing_cl / (PI * maxf(main_ar, 1.0)) * 0.85 * (0.5 + 0.5 * ge_phi), -0.25, 0.25)
	for p in panels:
		if not p["alive"]:
			continue
		var r: Vector3 = (p["pos"] as Vector3) - com_local
		# local wind incl. spanwise turbulence gradient
		var v_p := v_l + w_l.cross(r) - wind_l - wind_tip_l * (p["pos"] as Vector3).x
		for wsh in p["wash"]:
			var e2: Propulsion = engines[int(wsh[0])]
			v_p += e2.dir * e2.wash_v * float(wsh[1])
		var sd: Vector3 = p["span"]
		var v2 := v_p - sd * v_p.dot(sd)
		var V2 := v2.length()
		if V2 < 0.1:
			continue
		var fw: Vector3 = p["fwd"]
		var nr: Vector3 = p["nrm"]
		var alpha := atan2(-v2.dot(nr), v2.dot(fw))
		var role := String(p["role"])
		if role == "htail":
			alpha -= downwash
		var dal := 0.0
		var cdc := 0.0
		var cmc := 0.0
		var area_f := float(p["eff"])
		for c in p["ctrls"]:
			var s: Dictionary = surfaces[int(c["surf"])]
			if s["dead"]:
				area_f -= float(c["frac"]) * float(c["cf"])
				continue
			var dl := float(s["defl"])
			var ad := absf(dl)
			var dd := float(c["tau"]) * float(c["frac"]) * float(s["health"]) * dl * (1.0 - 0.28 * minf(ad / 0.6, 1.0))
			dal += dd
			cdc += 1.1 * float(c["frac"]) * float(c["cf"]) * sin(ad) * sin(ad)
			cmc -= (0.15 + 0.35 * float(c["cf"])) * dd * float(p["cla"]) * (1.0 - float(c["cf"]))
		area_f = maxf(area_f, 0.0)
		var cla := float(p["cla"])
		var ar := float(p["ar"])
		if role == "wing" and ge_on:
			cla *= 1.0 + 0.12 * (1.0 - ge_phi)
		var a0 := float(p["a0"])
		var st := float(p["stall"])
		var a_eff := alpha - a0 + dal
		var ap := st - a0
		var an := st + a0
		var M := 28.0
		var e1 := exp(clampf(-M * (a_eff - ap), -40.0, 40.0))
		var e2x := exp(clampf(M * (a_eff + an), -40.0, 40.0))
		var sigma := (1.0 + e1 + e2x) / ((1.0 + e1) * (1.0 + e2x))
		var cl_lin := cla * a_eff
		var a_fp := alpha + dal * 0.5
		var sa := sin(a_fp)
		var ca := cos(a_fp)
		var cl_fp := 2.0 * signf(sa) * sa * sa * ca
		var cl := (1.0 - sigma) * cl_lin + sigma * cl_fp
		var k_ind := 1.0 / (PI * 0.8 * maxf(ar, 0.3))
		var cd_i := cl_lin * cl_lin * k_ind * (ge_phi if role == "wing" else 1.0)
		var cd := float(p["cd0"]) + cdc + (1.0 - sigma) * cd_i + sigma * 1.28 * sa * sa + 0.012 * a_eff * a_eff
		var q := 0.5 * RHO * V2 * V2
		var area := float(p["area"]) * area_f
		if role == "vtail" and has_htail:
			# fin blanketed by the stabiliser wake at high body alpha (spins)
			area *= 1.0 - 0.6 * smoothstep(0.3, 0.75, absf(aoa))
		var vh := v2 / V2
		var lift_dir := sd.cross(vh)
		var fp := (lift_dir * cl - vh * cd) * q * area
		var r_app := r - fw * (float(p["chord"]) * 0.25 * sigma)
		F += fp
		T += r_app.cross(fp)
		# section pitching moment (camber + control-surface deflection), fades after stall
		var cm := (float(p.get("cm0", 0.0)) + cmc) * (1.0 - sigma)
		if cm != 0.0:
			T += sd * (cm * q * area * float(p["chord"]))
		if update_state:
			p["cl"] = cl
			p["sigma"] = sigma
		if role == "wing":
			cl_sum += cl * area
			cl_area += area
	if update_state:
		wing_cl = cl_sum / maxf(cl_area, 1e-4)
	return [F, T]

## Factory trim: find the elevator offset that makes the airframe fly hands-off
## near a sensible cruise speed (what a pre-trimmed ARF comes with).
var pitch_trim := 0.0
var has_htail := true

func compute_factory_trim() -> void:
	var cl_target := 0.36
	var v_t := sqrt(2.0 * mass * G / (RHO * ref_area * cl_target))
	var saved_cl := wing_cl
	var best := 0.0
	var lo := -0.6
	var hi := 0.6
	for it in 22:
		var mid := (lo + hi) * 0.5
		var m := _trim_moment(mid, v_t)
		if m > 0.0:
			hi = mid   # nose-up moment -> need less up elevator
		else:
			lo = mid
		best = mid
	pitch_trim = clampf(best, -0.65, 0.65)
	# roll trim against prop torque at cruise (what a pilot trims out on the first flight)
	var tq := 0.0
	for ei in engines.size():
		var e: Propulsion = engines[ei]
		if not e.is_prop():
			continue
		var pr := Propulsion.new()
		pr.setup(eng_defs[ei])
		pr.running = true
		var bat := {"v": 3.85 * bat_cells, "v_nom": 3.8 * bat_cells, "lvc": 1.0}
		for k in 600:
			pr.step(0.01, 0.5, v_t * 1.25, bat, true)
		tq += pr.spin * pr.torque
	if absf(tq) > 1e-4:
		var a_t := _trim_alpha
		var v_l := Vector3(0, -sin(a_t * 0.6), -cos(a_t * 0.6)) * v_t * 1.25
		_set_elev(pitch_trim)
		var m0 := (_aero(v_l, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, 1.0, false)[1] as Vector3).z
		for s in surfaces:
			for m in s["mix"]:
				if int(m[0]) == 0:
					s["defl"] = float(s["defl"]) + float(m[1]) * float(max_defl[0])
		var m1 := (_aero(v_l, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, 1.0, false)[1] as Vector3).z
		var dm := m1 - m0
		if absf(dm) > 1e-5:
			roll_trim = clampf(-(tq) / dm * 0.75, -0.2, 0.2)
		for s in surfaces:
			s["defl"] = 0.0
	wing_cl = saved_cl

var roll_trim := 0.0
var _trim_alpha := 0.0

func _set_elev(elev: float) -> void:
	for s in surfaces:
		var t := 0.0
		for m in s["mix"]:
			if int(m[0]) == 1:
				t += float(m[1]) * elev * float(max_defl[1])
		s["defl"] = t

func _trim_moment(elev: float, v: float) -> float:
	# find body alpha giving lift = weight at speed v, return pitch moment there
	_set_elev(elev)
	var a_lo := -0.2
	var a_hi := 0.35
	var Tm := 0.0
	for it in 18:
		var a := (a_lo + a_hi) * 0.5
		var v_l := Vector3(0, -sin(a), -cos(a)) * v
		wing_cl = 0.0
		for k in 3:
			var r0 := _aero(v_l, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, 1.0, true)
		var res := _aero(v_l, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, 1.0, true)
		var lift := (res[0] as Vector3).dot(Vector3(0, cos(a), -sin(a)))
		Tm = (res[1] as Vector3).x
		if lift > mass * G:
			a_hi = a
		else:
			a_lo = a
		_trim_alpha = a
	for s in surfaces:
		s["defl"] = 0.0
	return Tm

# ================================================================ control mixing
func _mix_controls(dt: float, B: Basis, w_l: Vector3, air_l: Vector3) -> void:
	var roll := in_roll
	var pitch := in_pitch
	var yaw := in_yaw
	if not controls_enabled:
		roll = 0.0; pitch = 0.0; yaw = 0.0
	var p_rate := w_l.dot(Vector3(0, 0, -1))
	var q_rate := w_l.x
	var r_rate := -w_l.y
	var qdyn := 0.5 * RHO * maxf(airspeed * airspeed, 25.0)
	var gain := clampf(60.0 / qdyn, 0.08, 1.0)
	match assist:
		"arcade":
			var fwd := -B.z
			var right := B.x
			var up := B.y
			var bank := atan2(-right.y, up.y)
			var pit := asin(clampf(fwd.y, -1.0, 1.0))
			var tb := roll * deg_to_rad(55.0)
			var tp := pitch * deg_to_rad(32.0)
			var eb := wrapf(tb - bank, -PI, PI)
			roll = clampf(eb * 1.6 * gain * 1.6 - p_rate * 0.25 * gain, -1.0, 1.0)
			var turn_comp := (1.0 / maxf(cos(bank), 0.3) - 1.0) * 0.35 if absf(bank) < 1.2 else 0.0
			var ep := (tp - pit) * cos(bank) if up.y > 0.0 else -pit
			pitch = clampf(ep * 2.2 * gain * 1.5 + turn_comp - q_rate * 0.3 * gain, -1.0, 1.0)
			# stall protection
			var stall_margin := deg_to_rad(float(def["wings"][0]["stall_deg"]) - 3.0) - aoa
			if stall_margin < 0.0 and airspeed > 3.0:
				pitch = minf(pitch, stall_margin * 4.0)
			yaw = clampf(yaw + beta * 1.5 * gain - r_rate * 0.2 * gain, -1.0, 1.0)
		"sport":
			roll = clampf(roll - p_rate * 0.10 * gain * (1.0 - absf(in_roll)), -1.0, 1.0)
			pitch = clampf(pitch - q_rate * 0.12 * gain * (1.0 - absf(in_pitch)), -1.0, 1.0)
			yaw = clampf(yaw - r_rate * 0.10 * gain * (1.0 - absf(in_yaw)) + beta * 0.3 * gain, -1.0, 1.0)
		_:
			pass
	ch_cmd[0] = roll + (roll_trim if assist != "arcade" else 0.0)
	ch_cmd[1] = pitch + (pitch_trim if assist != "arcade" else pitch_trim * 0.5)
	ch_cmd[2] = yaw
	ch_cmd[3] = flap_pos
	var slew := deg_to_rad(servo_speed) * dt
	for s in surfaces:
		if s["dead"]:
			continue
		var target := 0.0
		var lim := 0.0
		for m in s["mix"]:
			var ch := int(m[0])
			target += float(m[1]) * float(ch_cmd[ch]) * float(max_defl[ch])
			lim = maxf(lim, float(max_defl[ch]))
		target = clampf(target, -lim * 1.3, lim * 1.3)
		# damaged surfaces flutter/jam
		var h := float(s["health"])
		if h < 0.5:
			target = lerpf(target * 0.5, sin(sim_t * 23.0) * lim * 0.15, 0.5 - h)
		s["defl"] = move_toward(float(s["defl"]), target, slew)

# ================================================================ battery
func _battery_state() -> Dictionary:
	if not is_electric():
		return {"v": 0.0, "v_nom": 1.0, "lvc": 1.0}
	var cell := _ocv(bat_soc)
	var v := cell * bat_cells - total_current * bat_r
	bat_v = maxf(v, 0.0)
	# ESC low-voltage cutoff: soft reduction below 3.3 V/cell under load
	var per := bat_v / bat_cells
	var target := 1.0 if per > 3.35 else clampf((per - 3.0) / 0.35, 0.0, 1.0)
	bat_lvc = lerpf(bat_lvc, target, 0.05)
	return {"v": bat_v, "v_nom": 3.8 * bat_cells, "lvc": bat_lvc}

func _update_battery(dt: float) -> void:
	if not is_electric():
		return
	bat_soc = maxf(bat_soc - total_current * dt / (bat_cap * 3600.0), 0.0)

static func _ocv(soc: float) -> float:
	var pts = [[0.0, 3.2], [0.05, 3.45], [0.12, 3.62], [0.25, 3.72], [0.5, 3.82], [0.75, 3.96], [0.9, 4.08], [1.0, 4.2]]
	for i in range(1, pts.size()):
		if soc <= float(pts[i][0]):
			var t = (soc - float(pts[i - 1][0])) / (float(pts[i][0]) - float(pts[i - 1][0]))
			return lerpf(float(pts[i - 1][1]), float(pts[i][1]), t)
	return 4.2

# ================================================================ landing gear
func _gear(state: PhysicsDirectBodyState3D, dt: float, xf: Transform3D, com_w: Vector3, v_w: Vector3, w_w: Vector3, space: PhysicsDirectSpaceState3D) -> void:
	var B := xf.basis
	var down := -B.y
	wheels_touching = 0
	var deployed := gear_pos > 0.97 or not has_retracts()
	for wi in wheels.size():
		var w: Dictionary = wheels[wi]
		w["contact"] = false
		if not w["alive"] or comps[int(w["comp"])]["detached"] or not deployed:
			w["comp_now"] = 0.0
			continue
		var L := float(w["travel"]) * (1.0 - float(w["bent"]) * 0.4)
		var r := float(w["r"])
		var top_w: Vector3 = xf * ((w["center"] as Vector3) + Vector3(0, float(w["travel"]), 0))
		var reach := L + r
		_ray_params.from = top_w
		_ray_params.to = top_w + down * reach
		var hit := space.intersect_ray(_ray_params)
		if hit.is_empty():
			if float(w.get("peak", 0.0)) > 0.0 and not bool(w.get("peak_done", false)):
				_gear_peak_eval(w, top_w)
			w["comp_now"] = 0.0
			w["prev_comp"] = 0.0
			w["peak"] = 0.0
			w["peak_done"] = false
			continue
		var hp: Vector3 = hit["position"]
		var n: Vector3 = hit["normal"]
		var dist := top_w.distance_to(hp)
		var comp := clampf(reach - dist, 0.0, L * 1.2)
		var comp_rate = (comp - float(w["prev_comp"])) / dt
		w["prev_comp"] = comp
		w["comp_now"] = comp
		var k := float(w["k"])
		var c := float(w["c"])
		var fs = k * comp + c * comp_rate
		# progressive bump stop near full travel
		if comp > L * 0.85:
			fs += k * 6.0 * (comp - L * 0.85)
		fs = maxf(fs, 0.0)
		var align := clampf(n.dot(-down), 0.0, 1.0)
		if align < 0.25:
			continue
		w["contact"] = true
		wheels_touching += 1
		w["load_now"] = fs
		# surface
		var surf = SURF_FROM(hit.get("collider"), hp)
		w["surface"] = surf
		var info: Dictionary = Game.SURF_INFO.get(surf, Game.SURF_INFO[0])
		var mu := float(info["mu"])
		var rr := float(info["rr"]) * (1.4 if float(w["r"]) < 0.03 else 1.0) * (0.55 if String(w["style"]) == "bush" else 1.0)
		# wheel frame
		var steer_ang := 0.0
		if w["steer"]:
			var lim := deg_to_rad(30.0 if w["tail"] else 25.0)
			steer_ang = -in_yaw * lim * clampf(1.2 - ground_speed / 25.0, 0.3, 1.0)
			if w["tail"]:
				steer_ang = -steer_ang  # tail wheel turns opposite to the nose
		w["steer_now"] = steer_ang
		var fwd := (-B.z).rotated(B.y, steer_ang)
		var fg := (fwd - n * fwd.dot(n)).normalized()
		var sg := fg.cross(n).normalized()
		var rel := hp - com_w
		var vc := v_w + w_w.cross(rel)
		var coll = hit.get("collider")
		if coll is RigidBody3D:
			vc -= (coll as RigidBody3D).linear_velocity
		var vlong := vc.dot(fg)
		var vlat := vc.dot(sg)
		var N = fs * align
		var flat = -mu * N * tanh(vlat / 0.12)
		var br = brake if w["brake"] else 0.0
		var flong = -rr * N * tanh(vlong / 0.08) - br * mu * 0.75 * N * tanh(vlong / 0.15)
		# friction circle
		var ft := Vector2(flong, flat)
		if ft.length() > mu * N:
			ft = ft.normalized() * mu * N
		var Fw = n * fs * align + fg * ft.x + sg * ft.y
		state.apply_force(Fw, hp - xf.origin)
		w["spin_rate"] = vlong / r
		# touchdown event
		if not w["was_contact"] and airborne_time > 0.6:
			var vs := -v_w.y
			touchdown.emit.call_deferred({"vs": vs, "pos": hp, "speed": ground_speed, "wheel": wi})
		# overload -> bend / collapse, evaluated once per touchdown at the force peak
		var load_ref := float(w["load"])
		var peak := float(w.get("peak", 0.0))
		if fs > peak:
			w["peak"] = fs
		elif peak > 0.0 and fs < peak * 0.6 and not bool(w.get("peak_done", false)):
			_gear_peak_eval(w, hp)
	for w in wheels:
		w["was_contact"] = w["contact"]
	on_ground = wheels_touching > 0 or _body_ground_contact

var _body_ground_contact := false

func _gear_peak_eval(w: Dictionary, at: Vector3) -> void:
	w["peak_done"] = true
	var ratio := float(w["peak"]) / maxf(float(w["load"]), 0.01)
	w["last_peak_g"] = maxf(float(w.get("last_peak_g", 0.0)), ratio)
	if damage_mode == "off" or ratio <= 14.0:
		return
	var sev := (ratio - 14.0) / 14.0
	if damage_mode == "physical":
		w["bent"] = clampf(float(w["bent"]) + sev * 0.35, 0.0, 1.0)
		w["hp"] = float(w["hp"]) - sev * 0.45
		if float(w["hp"]) <= 0.0:
			_request_detach(int(w["comp"]), {"sev": 6.0, "pos": at, "cause": "gear"})
	comps[int(w["comp"])]["dmg_vis"] = clampf(float(comps[int(w["comp"])]["dmg_vis"]) + sev * 0.3, 0.0, 1.0)
	if Game.fx:
		Game.fx.impact_sound(at, "gear", clampf(sev, 0.2, 1.0))

func SURF_FROM(collider, p: Vector3) -> int:
	if collider and collider is Object and (collider as Object).has_meta("surface"):
		return int((collider as Object).get_meta("surface"))
	return Game.surface_at(p)

# ================================================================ contacts & damage
var contact_grace := 0

func _contacts(state: PhysicsDirectBodyState3D) -> void:
	_body_ground_contact = false
	var n_c := state.get_contact_count()
	if contact_grace > 0:
		contact_grace -= 1
		return
	if n_c == 0:
		scrape_level = move_toward(scrape_level, 0.0, state.step * 4.0)
		return
	var scraping := 0.0
	for i in n_c:
		var sh := state.get_contact_local_shape(i)
		var owner_id := shape_find_owner(sh)
		if owner_id < 0:
			continue
		var node := shape_owner_get_owner(owner_id) as Node
		if node == null or not node.has_meta("ci"):
			continue
		var ci := int(node.get_meta("ci"))
		var is_wheel := bool(node.get_meta("wheel", false))
		var n := state.get_contact_local_normal(i).normalized()
		var v_rel := state.get_contact_local_velocity_at_position(i) - state.get_contact_collider_velocity_at_position(i)
		var closing := maxf(-v_rel.dot(n), 0.0)
		var J := state.get_contact_impulse(i).length()
		var pos := state.get_contact_collider_position(i)
		var collider := state.get_contact_collider_object(i)
		var tang := contact_tangent(v_rel, n).length()
		# A lateral obstacle impact is not support beneath the aircraft.
		_body_ground_contact = _body_ground_contact or n.dot(Vector3.UP) >= 0.6
		var hard := 1.0
		var kind := "ground"
		if collider and collider is Object:
			var co := collider as Object
			hard = float(co.get_meta("hardness", 1.0))
			kind = String(co.get_meta("kind", "ground"))
			if co.has_method("hit_by_aircraft"):
				co.hit_by_aircraft(self, v_rel.length(), -n, pos)
			if co.has_method("knock"):
				co.knock(-n * maxf(closing, J / maxf(mass, 0.05)) * mass, pos)
		var m_eff := maxf(mass * 0.6, 0.05)
		var sev := maxf(closing, J / m_eff) * hard
		# inertial shock: a violent deceleration of the whole airframe rips parts off
		var g_shock := J / maxf(mass, 0.05) / maxf(state.step, 1e-4) / G
		if g_shock > 45.0 and damage_mode == "physical":
			_inertial_shock(g_shock, pos)
		# prop strikes: a spinning prop in contact takes damage from tip speed
		var ck := String(comps[ci]["kind"])
		if ck == "prop":
			for ei in eng_defs.size():
				if int(eng_defs[ei]["prop_comp"]) == ci:
					var e: Propulsion = engines[ei]
					var tipv := e.omega * e.D * 0.5
					if tipv > 8.0:
						sev = maxf(sev, tipv * 0.09)
						e.strike_torque = maxf(e.strike_torque, e.torque * 3.0 + 0.3 * e.D)
					if Game.fx and tipv > 8.0:
						Game.fx.dust(pos, Vector3.UP * 2.0, 0.6)
		if is_wheel:
			sev *= 0.5
		scraping = maxf(scraping, tang * clampf(J * 30.0, 0.0, 1.0))
		if sev > 1.0:
			impact_log.append({"t": sim_t, "comp": comps[ci]["id"], "sev": sev, "kind": kind})
			if impact_log.size() > 40:
				impact_log.pop_front()
			if Diag:
				Diag.log_collision(String(def["id"]), String(comps[ci]["id"]), sev, kind)
		if sev > max_impact:
			last_contact_speed = v_rel.length()
		max_impact = maxf(max_impact, sev)
		_damage(ci, sev, pos, n, kind)
		# scraping wear is cosmetic (scuffs + grass stains); structure breaks from impacts
		if tang > 1.0 and damage_mode != "off":
			comps[ci]["dirt"] = clampf(float(comps[ci]["dirt"]) + tang * state.step * 0.08, 0.0, 1.0)
			comps[ci]["dmg_vis"] = clampf(float(comps[ci]["dmg_vis"]) + tang * state.step * 0.004, 0.0, 0.35)
		# gear bottoming out on the bump stop bends the leg
		if is_wheel and closing + J / m_eff > 2.2 and damage_mode == "physical":
			for w in wheels:
				if int(w["comp"]) == ci:
					var ex := closing + J / m_eff - 2.2
					w["bent"] = clampf(float(w["bent"]) + ex * 0.12, 0.0, 1.0)
					w["hp"] = float(w["hp"]) - ex * 0.12
					if float(w["hp"]) <= 0.0:
						_request_detach(ci, {"sev": 6.0, "pos": pos, "cause": "gear"})
	scrape_level = lerpf(scrape_level, clampf(scraping / 8.0, 0.0, 1.0), 0.3)

var _last_shock := -1.0

func _inertial_shock(g: float, pos: Vector3) -> void:
	if sim_t - _last_shock < 0.05:
		return
	_last_shock = sim_t
	var mat_k := 1.0
	match String(def["material"]):
		"foam": mat_k = 1.25
		"film", "fabric": mat_k = 0.9
		"composite", "painted", "metal": mat_k = 1.1
	for ci in range(1, comps.size()):
		var c: Dictionary = comps[ci]
		if c["detached"]:
			continue
		var k := String(c["kind"])
		var thr := 0.0
		match k:
			"wing": thr = 95.0
			"wingtip": thr = 120.0
			"stab", "fin": thr = 110.0
			"canopy": thr = 70.0
			"nacelle": thr = 90.0
			"fuselage": thr = 140.0
			"engine": thr = 110.0
			_: continue
		thr *= mat_k * float(c["strength"])
		if g > thr:
			var p := clampf((g - thr) / thr, 0.0, 1.0)
			if Game.rng.randf() < p * 0.8:
				c["hp"] = 0.0
				_apply_component_health(ci)
				_request_detach(ci, {"sev": g * 0.08, "pos": pos, "cause": "shock"})
			else:
				c["hp"] = float(c["hp"]) - p * 0.6
				c["dmg_vis"] = clampf(float(c["dmg_vis"]) + p * 0.5, 0.0, 1.0)
				_apply_component_health(ci)

func _thresholds(ci: int) -> Vector2:
	var mat := String(def["material"])
	var soft := 3.0
	var brk := 8.5
	match mat:
		"foam": soft = 3.2; brk = 9.0
		"film": soft = 2.6; brk = 7.2
		"fabric": soft = 2.6; brk = 7.0
		"composite": soft = 3.0; brk = 9.0
		"metal", "painted": soft = 3.0; brk = 9.5
	var k := String(comps[ci]["kind"])
	var km := 1.0
	match k:
		"wingtip": km = 0.85
		"control": km = 0.7
		"prop": km = 0.45
		"canopy": km = 0.6
		"gear": km = 1.3
		"fuselage": km = 1.25
		"engine": km = 1.1
		"nacelle": km = 1.0
	var s := float(comps[ci]["strength"]) * km
	return Vector2(soft * sqrt(s), brk * s)

func _damage(ci: int, sev: float, pos: Vector3, n: Vector3, kind: String, transmitted := false) -> void:
	if damage_mode == "off" or comps[ci]["detached"]:
		return
	var th := _thresholds(ci)
	if sev < th.x:
		return
	var frac := clampf((sev - th.x) / maxf(th.y - th.x, 0.1), 0.0, 3.0)
	var loss := pow(frac, 1.4) * 0.85
	var c: Dictionary = comps[ci]
	c["dmg_vis"] = clampf(float(c["dmg_vis"]) + loss * 0.9 + 0.08, 0.0, 1.0)
	if not transmitted and Game.fx and sev > th.x * 1.2 and sim_t - last_impact_sfx > 0.08:
		last_impact_sfx = sim_t
		Game.fx.impact(pos, n, String(def["material"]), clampf(frac, 0.1, 1.0), _paint_color(ci))
	if damage_mode == "visual":
		if sev > th.y * 1.35 and not crashed_flag:
			_crash({"sev": sev, "pos": pos, "cause": kind})
		return
	c["hp"] = float(c["hp"]) - loss
	_apply_component_health(ci)
	# load path: part of the shock reaches the parent structure
	var par := int(c["parent"])
	if par >= 0 and not transmitted and frac > 0.3:
		_damage(par, sev * 0.55, pos, n, kind, true)
	if float(c["hp"]) <= 0.0:
		if ci == 0:
			if not crashed_flag:
				_crash({"sev": sev, "pos": pos, "cause": kind})
		else:
			_request_detach(ci, {"sev": sev, "pos": pos, "cause": kind, "normal": n})
	elif ci == 0 and sev > th.y * 1.5 and not crashed_flag:
		_crash({"sev": sev, "pos": pos, "cause": kind})

func _apply_component_health(ci: int) -> void:
	var c: Dictionary = comps[ci]
	var hp := clampf(float(c["hp"]), 0.0, 1.0)
	for p in panels:
		if int(p["comp"]) == ci:
			p["eff"] = lerpf(0.55, 1.0, hp)
			p["cd0"] = 0.009 + (1.0 - hp) * 0.03
	for s in surfaces:
		if int(s["comp"]) == ci:
			s["health"] = hp
	for ei in eng_defs.size():
		if int(eng_defs[ei]["prop_comp"]) == ci:
			(engines[ei] as Propulsion).health = hp
		if int(eng_defs[ei]["comp"]) == ci and hp < 0.35:
			(engines[ei] as Propulsion).mount_ok = hp > 0.1
			if hp < 0.2 and not (engines[ei] as Propulsion).is_prop():
				(engines[ei] as Propulsion).health = hp

func _paint_color(ci: int) -> Color:
	var lvd: Dictionary = def["livery"]
	return (lvd.get("base", Color.WHITE) as Color)

func _request_detach(ci: int, info: Dictionary) -> void:
	if comps[ci]["detached"] or ci == 0:
		return
	for q in detach_queue:
		if int(q[0]) == ci:
			return
	detach_queue.append([ci, info])

func _process_detach_queue() -> void:
	var q := detach_queue.duplicate()
	detach_queue.clear()
	for item in q:
		detach(int(item[0]), item[1])

func detach(ci: int, info := {}) -> void:
	if comps[ci]["detached"] or ci == 0:
		return
	var group = [ci]
	for dsc in _descendants(ci):
		if not comps[dsc]["detached"]:
			group.append(dsc)
	var rb: RigidBody3D = debris_bodies[ci]
	var center: Vector3 = comps[ci]["center"]
	var xf := global_transform
	var gm := 0.0
	for g in group:
		comps[g]["detached"] = true
		comps[g]["debris"] = ci
		gm += float(comps[g]["mass"])
		for s in comps[g]["col"]:
			(s["node"] as CollisionShape3D).set_deferred("disabled", true)
		for p in panels:
			if int(p["comp"]) == g:
				p["alive"] = false
		for s in surfaces:
			if int(s["comp"]) == g:
				s["dead"] = true
		for w in wheels:
			if int(w["comp"]) == g:
				w["alive"] = false
		for ei in eng_defs.size():
			if int(eng_defs[ei]["comp"]) == g:
				(engines[ei] as Propulsion).mount_ok = false
			if int(eng_defs[ei]["prop_comp"]) == g:
				(engines[ei] as Propulsion).health = 0.0
	if rb:
		var smap: Dictionary = rb.get_meta("shape_map")
		for m in smap.keys():
			for cs in smap[m]:
				(cs as CollisionShape3D).disabled = not (m in group)
		rb.set_meta("members", group)
		var p_w := xf * center
		var com_w := xf * com_local
		rb.global_transform = Transform3D(xf.basis, p_w)
		rb.mass = maxf(gm, 0.02)
		rb.collision_layer = Game.L_DEBRIS
		rb.collision_mask = Game.L_WORLD | Game.L_DEBRIS | Game.L_NPC | Game.L_AIRCRAFT
		rb.add_collision_exception_with(self)
		add_collision_exception_with(rb)
		rb.freeze = false
		rb.sleeping = false
		rb.linear_velocity = linear_velocity + angular_velocity.cross(p_w - com_w)
		rb.angular_velocity = angular_velocity + Vector3(Game.rng.randf_range(-3, 3), Game.rng.randf_range(-3, 3), Game.rng.randf_range(-3, 3))
		rb.continuous_cd = linear_velocity.length() > 15.0
		rb.call("ignore_temporarily", self, 0.35, true)
		if rb.has_method("activate"):
			rb.activate()
	pending_mass_update = true
	recompute_mass()
	if String(comps[ci]["kind"]) in ["wing", "wingtip", "stab", "fin", "fuselage", "nacelle", "engine"]:
		recent_breaks.append(sim_t)
	var id := String(comps[ci]["id"])
	component_broken.emit(id, info)
	if Game.fx:
		var p2 := xf * center
		Game.fx.breakup(p2, linear_velocity, String(def["material"]), _paint_color(ci), clampf(gm / maxf(mass, 0.1), 0.2, 1.0))
	_check_catastrophic(info)

func _clear_exception(rb: RigidBody3D) -> void:
	if is_instance_valid(rb):
		rb.remove_collision_exception_with(self)
		remove_collision_exception_with(rb)

func _check_catastrophic(info: Dictionary) -> void:
	if crashed_flag:
		return
	var wings_gone := 0
	var wings_total := 0
	var tail_gone := false
	for c in comps:
		if String(c["kind"]) == "wing":
			wings_total += 1
			if c["detached"]:
				wings_gone += 1
		if String(c["id"]) == "tail_boom" and c["detached"]:
			tail_gone = true
	var reason := ""
	if tail_gone:
		reason = "tail"
	elif wings_total > 0 and wings_gone >= mini(2, wings_total):
		reason = "wings"
	elif recent_breaks.size() >= 3:
		reason = "breakup"
	elif wings_gone >= 1 and agl < 2.0 and float(info.get("sev", 0.0)) > 8.0:
		reason = "cartwheel"
	if reason != "":
		_crash({"sev": float(info.get("sev", 10.0)), "pos": info.get("pos", global_position), "cause": reason})

func _crash(info: Dictionary) -> void:
	if crashed_flag:
		return
	crashed_flag = true
	controls_enabled = false
	for e in engines:
		(e as Propulsion).kill()
	info["time"] = sim_t
	info["contact_speed_mps"] = last_contact_speed
	crashed.emit.call_deferred(info)

# ================================================================ repair / reset
func repair_all() -> void:
	for ci in comps.size():
		var c: Dictionary = comps[ci]
		c["hp"] = 1.0
		c["dmg_vis"] = 0.0
		c["dirt"] = 0.0
		if c["detached"]:
			_reattach(ci)
	for p in panels:
		p["alive"] = true
		p["eff"] = 1.0
		p["cd0"] = 0.009 if String(p["role"]) != "body" else 0.0
	for s in surfaces:
		s["dead"] = false
		s["health"] = 1.0
		s["defl"] = 0.0
	for w in wheels:
		w["alive"] = true
		w["hp"] = 1.0
		w["bent"] = 0.0
		w["prev_comp"] = 0.0
	for e in engines:
		e.health = 1.0
		e.mount_ok = true
		e.omega = 0.0
		e.rpm_frac = 0.0
		e.running = e.type == "electric" or e.type == "edf"
		e.starting = 0.0
	crashed_flag = false
	controls_enabled = true
	max_impact = 0.0
	recent_breaks.clear()
	detach_queue.clear()
	bat_soc = 1.0
	bat_lvc = 1.0
	if fuel_max > 0.0:
		fuel_kg = fuel_max * clampf(float(cfg.get("fuel", 1.0)), 0.05, 1.0)
	recompute_mass()

func _reattach(ci: int) -> void:
	var c: Dictionary = comps[ci]
	c["detached"] = false
	var owner_ci := int(c["debris"])
	c["debris"] = -1
	for s in c["col"]:
		(s["node"] as CollisionShape3D).set_deferred("disabled", false)
	if owner_ci == ci and debris_bodies[ci]:
		var rb: RigidBody3D = debris_bodies[ci]
		rb.call("clear_temporary_exceptions")
		rb.set("active", false)
		rb.freeze = true
		rb.collision_layer = 0
		rb.collision_mask = 0
		rb.set_meta("members", [])
		for m in (rb.get_meta("shape_map") as Dictionary).values():
			for cs in m:
				(cs as CollisionShape3D).disabled = true
		rb.global_transform = Transform3D(Basis(), Vector3(0, -500, 0))

func place(xf: Transform3D, speed := 0.0) -> void:
	# teleport (used by spawn, mode setup and rewind)
	global_transform = xf
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, xf)
	var v := -xf.basis.z * speed
	linear_velocity = v
	angular_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, v)
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	prev_xf = xf
	curr_xf = xf
	last_vel = v
	contact_grace = 3
	for w2 in wheels:
		w2["peak"] = 0.0
		w2["peak_done"] = false
	for w in wheels:
		w["prev_comp"] = 0.0
		w["was_contact"] = false
	airborne_time = 0.0

# ================================================================ snapshots (rewind)
const SNAPSHOT_RUNTIME := ["in_roll", "in_pitch", "in_yaw", "in_throttle", "brake", "controls_enabled", "assist", "damage_mode",
	"bat_v", "total_current", "agl", "terrain_agl", "altitude_valid", "airspeed", "aoa", "beta", "ground_speed",
	"on_ground", "wheels_touching", "airborne_time", "ground_time", "wing_cl", "g_load", "last_vel", "max_impact",
	"last_contact_speed", "scrape_level", "last_impact_sfx", "_last_shock", "_body_ground_contact", "contact_grace", "_fol_F", "_fol_T"]
const WHEEL_RUNTIME := ["surface", "contact", "was_contact", "comp_now", "spin_rate", "steer_now", "peak", "peak_done", "last_peak_g"]

func snapshot() -> Dictionary:
	var hp := PackedFloat32Array()
	var det := PackedByteArray()
	var dv := PackedFloat32Array()
	for c in comps:
		hp.append(float(c["hp"]))
		det.append(1 if c["detached"] else 0)
		dv.append(float(c["dmg_vis"]))
	var es = []
	for e in engines:
		es.append(e.snapshot())
	var ws = []
	for w in wheels:
		ws.append([w["hp"], w["bent"], w["alive"], w["prev_comp"]])
	var ss = []
	for s in surfaces:
		ss.append([s["defl"], s["health"], s["dead"]])
	var runtime := {}
	for key in SNAPSHOT_RUNTIME:
		runtime[key] = get(key)
	var wr := []
	for wheel in wheels:
		var values := {}
		for key in WHEEL_RUNTIME:
			if wheel.has(key): values[key] = wheel[key]
		wr.append(values)
	var panel_state := []
	for panel in panels:
		var values := {}
		for key in ["alive", "eff", "cd0", "cl", "sigma"]:
			if panel.has(key): values[key] = panel[key]
		panel_state.append(values)
	var owners := PackedInt32Array()
	var dirt := PackedFloat32Array()
	for c in comps:
		owners.append(int(c["debris"]))
		dirt.append(float(c["dirt"]))
	var debris := {}
	for i in debris_bodies.size():
		var rb: RigidBody3D = debris_bodies[i]
		if rb and not (rb.get_meta("members", []) as Array).is_empty():
			debris[i] = {"xf": rb.global_transform, "v": rb.linear_velocity, "w": rb.angular_velocity,
				"mass": rb.mass, "sleep": rb.sleeping, "freeze": rb.freeze, "members": (rb.get_meta("members") as Array).duplicate(),
				"exception_owner": -1 if rb.get("exception_body") == self else debris_bodies.find(rb.get("exception_body")),
				"exception_time": rb.get("exception_remaining"), "exception_mutual": rb.get("exception_mutual"),
				"age": rb.get("t_active"), "last_hit": rb.get("last_hit"), "layer": rb.collision_layer, "mask": rb.collision_mask}
	return {"version": 2, "panel_state": panel_state, "runtime": runtime, "wheel_runtime": wr, "owners": owners, "dirt": dirt, "debris": debris,
		"prop_angle": prop_angle.duplicate(), "wheel_angle": wheel_spin_angle.duplicate(), "ch_cmd": ch_cmd.duplicate(),
		"breaks": recent_breaks.duplicate(), "xf": global_transform, "v": linear_velocity, "w": angular_velocity, "hp": hp, "det": det, "dv": dv,
		"eng": es, "wheels": ws, "surf": ss, "soc": bat_soc, "fuel": fuel_kg, "flap": flap_pos, "flap_cmd": flap_cmd,
		"gear": gear_pos, "gear_down": gear_down, "t": sim_t, "crashed": crashed_flag, "lvc": bat_lvc,
		"wind_t": Game.wind.t if Game.wind else 0.0}

func restore(s: Dictionary) -> void:
	# re-attach anything that broke after the snapshot
	for ci in comps.size():
		var was_det := int(s["det"][ci]) == 1
		if comps[ci]["detached"] and not was_det:
			_reattach(ci)
		elif not comps[ci]["detached"] and was_det:
			comps[ci]["detached"] = true
			for sh in comps[ci]["col"]:
				(sh["node"] as CollisionShape3D).set_deferred("disabled", true)
		comps[ci]["hp"] = float(s["hp"][ci])
		comps[ci]["dmg_vis"] = float(s["dv"][ci])
	for p in panels:
		p["alive"] = not comps[int(p["comp"])]["detached"]
	for ci in comps.size():
		_apply_component_health(ci)
	for i in engines.size():
		(engines[i] as Propulsion).restore(s["eng"][i])
	for i in wheels.size():
		var w: Dictionary = wheels[i]
		var ws: Array = s["wheels"][i]
		w["hp"] = ws[0]; w["bent"] = ws[1]; w["alive"] = ws[2]; w["prev_comp"] = ws[3]
	for i in surfaces.size():
		var sv: Array = s["surf"][i]
		surfaces[i]["defl"] = sv[0]; surfaces[i]["health"] = sv[1]; surfaces[i]["dead"] = sv[2]
	bat_soc = s["soc"]
	bat_lvc = s["lvc"]
	fuel_kg = s["fuel"]
	flap_pos = s["flap"]
	flap_cmd = s["flap_cmd"]
	gear_pos = s["gear"]
	gear_down = s["gear_down"]
	sim_t = s["t"]
	crashed_flag = bool(s.get("crashed", false))
	controls_enabled = not crashed_flag
	detach_queue.clear()
	recent_breaks.clear()
	if Game.wind:
		Game.wind.t = s["wind_t"]
	recompute_mass()
	place(s["xf"])
	linear_velocity = s["v"]
	angular_velocity = s["w"]
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, s["v"])
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, s["w"])
	last_vel = s["v"]
	if int(s.get("version", 1)) >= 2:
		for key in s["runtime"]:
			set(key, s["runtime"][key])
		if s.has("panel_state"):
			for i in panels.size(): panels[i].merge(s["panel_state"][i], true)
		for i in wheels.size():
			wheels[i].merge(s["wheel_runtime"][i], true)
		for i in comps.size():
			comps[i]["debris"] = int(s["owners"][i])
			comps[i]["dirt"] = float(s["dirt"][i])
			(comps[i]["visual"] as Node3D).visible = true
		prop_angle = s["prop_angle"].duplicate()
		wheel_spin_angle = s["wheel_angle"].duplicate()
		ch_cmd = s["ch_cmd"].duplicate()
		recent_breaks = s["breaks"].duplicate()
		_restore_debris(s["debris"])
	pending_mass_update = false
	foliage.clear()
	vis_xf = s["xf"]
	update_visuals(vis_xf, 0.0)

func _restore_debris(saved: Dictionary) -> void:
	for i in debris_bodies.size():
		var rb: RigidBody3D = debris_bodies[i]
		if rb == null: continue
		rb.call("clear_temporary_exceptions")
		rb.freeze = true
		rb.collision_layer = 0
		rb.collision_mask = 0
		rb.set("active", false)
		var d: Dictionary = saved.get(i, {})
		var members: Array = d.get("members", [])
		rb.set_meta("members", members.duplicate())
		var shape_map: Dictionary = rb.get_meta("shape_map")
		for ci in shape_map:
			for cs in shape_map[ci]:
				(cs as CollisionShape3D).set_deferred("disabled", not (ci in members))
		if d.is_empty():
			rb.global_position = Vector3(0, -500, 0)
			continue
		rb.mass = d["mass"]
		rb.global_transform = d["xf"]
		rb.linear_velocity = d["v"]
		rb.angular_velocity = d["w"]
		rb.collision_layer = d["layer"]
		rb.collision_mask = d["mask"]
		rb.freeze = d["freeze"]
		rb.sleeping = d["sleep"]
		rb.set("active", not rb.freeze)
		rb.set("t_active", d["age"])
		rb.set("last_hit", d["last_hit"])
	# Restore exceptions only after every pooled body has been reset.
	for i in saved:
		var d: Dictionary = saved[i]
		if float(d.get("exception_time", 0.0)) > 0.0:
			var owner_index := int(d.get("exception_owner", -1))
			var body: PhysicsBody3D = self if owner_index < 0 else debris_bodies[owner_index]
			debris_bodies[i].call("ignore_temporarily", body, d["exception_time"], d["exception_mutual"])

# ================================================================ visuals
func _process(delta: float) -> void:
	if replay_driven:
		return
	var f := Engine.get_physics_interpolation_fraction()
	if display_only:
		vis_xf = global_transform
	else:
		vis_xf = prev_xf.interpolate_with(curr_xf, f) if prev_xf != Transform3D() else global_transform
	update_visuals(vis_xf, delta)

## Drives all visual nodes. Also used by the replay system with recorded values.
func update_visuals(xf: Transform3D, delta: float) -> void:
	visual_root.global_transform = xf
	for ci in comps.size():
		var c: Dictionary = comps[ci]
		var vis: Node3D = c["visual"]
		if c["detached"]:
			var owner_ci := int(c["debris"])
			var rb: RigidBody3D = debris_bodies[owner_ci] if owner_ci >= 0 and owner_ci < debris_bodies.size() else null
			if rb and is_instance_valid(rb):
				var center: Vector3 = comps[owner_ci]["center"]
				vis.global_transform = rb.global_transform * Transform3D(Basis(), -center)
			else:
				vis.visible = false
		else:
			vis.transform = Transform3D()
			vis.visible = true
	_animate(delta)

func _animate(delta: float) -> void:
	for cut in build.get("fractures", []):
		var parent := int(cut["parent"])
		var child := int(cut["child"])
		var p_owner := int(replay_owners[parent]) if replay_driven and replay_owners.size() == comps.size() else int(comps[parent]["debris"])
		var c_owner := int(replay_owners[child]) if replay_driven and replay_owners.size() == comps.size() else int(comps[child]["debris"])
		for node in cut["nodes"]: (node as MeshInstance3D).visible = p_owner != c_owner
	for s in surfaces:
		var part: Node3D = build_part(int(s["part"]))
		if part:
			part.basis = Basis((s["axis"] as Vector3), float(s["defl"]))
	for ei in engines.size():
		var e: Propulsion = engines[ei]
		var ed: Dictionary = eng_defs[ei]
		var rpm := e.rpm()
		prop_angle[ei] = fposmod(float(prop_angle[ei]) + e.omega * delta * e.spin, TAU)
		var rp = build_part(int(ed["rot_part"]))
		if rp:
			rp.basis = Basis(Vector3(0, 0, -1), float(prop_angle[ei]))
			if e.is_prop():
				rp.visible = true
				var bm := rp.get_node_or_null("Mesh") as MeshInstance3D
				if bm:
					bm.visible = rpm < 2200.0 or e.health < 0.35
		var dp = build_part(int(ed["disc_part"]))
		if dp:
			var mi := dp.get_node_or_null("Mesh") as MeshInstance3D
			if mi:
				var blur := smoothstep(500.0, 2600.0, rpm) if e.is_prop() else smoothstep(1500.0, 9000.0, rpm)
				blur *= clampf(e.health * 1.2, 0.0, 1.0)
				mi.visible = blur > 0.01
				mi.set_instance_shader_parameter("blur", blur)
	for wi in wheels.size():
		var w: Dictionary = wheels[wi]
		var sl = build_part(int(w["slider_part"]))
		if sl:
			sl.position = Vector3(0, float(w["comp_now"]), 0)
		var stp = build_part(int(w["steer_part"]))
		if stp:
			stp.basis = Basis(Vector3.UP, float(w.get("steer_now", 0.0)))
		wheel_spin_angle[wi] = fposmod(float(wheel_spin_angle[wi]) + float(w["spin_rate"]) * delta, TAU)
		var sp = build_part(int(w["spin_part"]))
		if sp:
			sp.basis = Basis(Vector3.RIGHT, -float(wheel_spin_angle[wi]))
		var rt = build_part(int(w["retract_part"]))
		if rt:
			var ang = (1.0 - gear_pos) * float(w["retract_angle"]) if has_retracts() else 0.0
			ang += float(w["bent"]) * 0.35
			rt.basis = Basis((w["retract_axis"] as Vector3), ang)
	# damage visuals
	for c in comps:
		var mi2: MeshInstance3D = _comp_mesh(c)
		if mi2:
			var dv := float(c["dmg_vis"])
			if float(c.get("_last_dv", -1.0)) != dv or float(c.get("_last_dirt", -1.0)) != float(c["dirt"]):
				c["_last_dv"] = dv
				c["_last_dirt"] = float(c["dirt"])
				_set_damage_recursive(c["visual"], dv, float(c["dirt"]))

func _set_damage_recursive(n: Node, dv: float, dirt: float) -> void:
	for ch in n.get_children():
		if ch is MeshInstance3D:
			(ch as MeshInstance3D).set_instance_shader_parameter("damage", dv)
			(ch as MeshInstance3D).set_instance_shader_parameter("dirt", dirt)
		elif ch is Node3D and not (ch is Label3D):
			# control surfaces & gear inherit, but do not recurse into other components
			if not _is_comp_visual(ch):
				_set_damage_recursive(ch, dv, dirt)

func _is_comp_visual(n: Node) -> bool:
	for c in comps:
		if c["visual"] == n:
			return true
	return false

func _comp_mesh(c: Dictionary) -> MeshInstance3D:
	var v: Node3D = c["visual"]
	return v.get_node_or_null("Mesh") as MeshInstance3D if v else null

func build_part(i: int) -> Node3D:
	if i < 0:
		return null
	var parts: Array = build["parts"]
	return parts[i]["node"] if i < parts.size() else null

# ================================================================ telemetry
func telemetry() -> Dictionary:
	var rpm := 0.0
	var running := false
	for e in engines:
		rpm = maxf(rpm, e.rpm())
		running = running or e.running
	var t := {"airspeed": airspeed, "gs": ground_speed, "alt": terrain_agl, "alt_valid": altitude_valid, "vs": linear_velocity.y, "rpm": rpm,
		"throttle": in_throttle, "running": running, "aoa": rad_to_deg(aoa), "g": g_load, "flaps": flap_cmd,
		"gear": gear_down, "electric": is_electric()}
	if is_electric():
		t["volts"] = bat_v
		t["cells"] = bat_cells
		t["soc"] = bat_soc
		t["amps"] = total_current
	else:
		t["fuel"] = fuel_kg / maxf(fuel_max, 1e-4)
	return t

func health_summary() -> Array:
	var out = []
	for c in comps:
		out.append({"id": c["id"], "kind": c["kind"], "hp": c["hp"], "detached": c["detached"], "dmg": c["dmg_vis"]})
	return out

# ================================================================ secondary breakup
func split_debris(rb: RigidBody3D, sev: float) -> void:
	var members: Array = rb.get_meta("members", [])
	var owner_ci := int(rb.get_meta("ci"))
	var cands = []
	for m in members:
		if int(m) != owner_ci and int(comps[int(m)]["parent"]) == owner_ci:
			cands.append(int(m))
	if cands.is_empty():
		return
	var child: int = cands[Game.rng.randi() % cands.size()]
	var moved = [child]
	for dsc in _descendants(child):
		if dsc in members:
			moved.append(dsc)
	var crb: RigidBody3D = debris_bodies[child]
	if crb == null:
		return
	var owner_center: Vector3 = comps[owner_ci]["center"]
	var child_center: Vector3 = comps[child]["center"]
	var smap: Dictionary = rb.get_meta("shape_map")
	var gm := 0.0
	for m in moved:
		members.erase(m)
		comps[m]["debris"] = child
		for cs in smap.get(m, []):
			(cs as CollisionShape3D).disabled = true
	for m in members:
		gm += float(comps[int(m)]["mass"])
	rb.mass = maxf(gm, 0.02)
	rb.set_meta("members", members)
	var cmap: Dictionary = crb.get_meta("shape_map")
	var cm := 0.0
	for m in cmap.keys():
		for cs in cmap[m]:
			(cs as CollisionShape3D).disabled = not (m in moved)
	for m in moved:
		cm += float(comps[int(m)]["mass"])
	crb.set_meta("members", moved)
	crb.global_transform = rb.global_transform * Transform3D(Basis(), child_center - owner_center)
	crb.mass = maxf(cm, 0.02)
	crb.collision_layer = Game.L_DEBRIS
	crb.collision_mask = Game.L_WORLD | Game.L_DEBRIS | Game.L_NPC | Game.L_AIRCRAFT
	crb.freeze = false
	crb.linear_velocity = rb.linear_velocity + Vector3(Game.rng.randf_range(-1, 1), Game.rng.randf_range(0, 1.5), Game.rng.randf_range(-1, 1))
	crb.angular_velocity = rb.angular_velocity + Vector3(Game.rng.randf_range(-4, 4), Game.rng.randf_range(-4, 4), Game.rng.randf_range(-4, 4))
	crb.add_collision_exception_with(rb)
	crb.call("ignore_temporarily", rb, 0.3, false)
	if crb.has_method("activate"):
		crb.activate()
	if Game.fx:
		Game.fx.breakup(crb.global_position, crb.linear_velocity, String(def["material"]), _paint_color(child), 0.3)
	component_broken.emit(String(comps[child]["id"]), {"sev": sev, "secondary": true})

func active_debris() -> Array:
	var out = []
	for rb in debris_bodies:
		if rb and not (rb as RigidBody3D).freeze:
			out.append(rb)
	return out

## Diagnostics: static margin from the panel model (fraction of MAC; + = stable)
func static_margin() -> float:
	var v := 15.0
	var res := []
	for a in [0.02, 0.08]:
		var v_l := Vector3(0, -sin(a), -cos(a)) * v
		wing_cl = 0.0
		for k in 4:
			_aero(v_l, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, 1.0, true)
		var r := _aero(v_l, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, 1.0, true)
		var lift := (r[0] as Vector3).dot(Vector3(0, cos(a), -sin(a)))
		res.append([lift, (r[1] as Vector3).x])
	var dL: float = res[1][0] - res[0][0]
	var dM: float = res[1][1] - res[0][1]
	# moment about CG changes by -x_np*dL; x_np = distance NP behind CG
	return (-dM / maxf(dL, 1e-5)) / maxf(mac_c, 0.01)

# ================================================================ replay playback (visual only)
func apply_replay(fa: Dictionary, fb: Dictionary, a: float, delta: float) -> void:
	var xf := (fa["xf"] as Transform3D).interpolate_with(fb["xf"], a)
	vis_xf = xf
	visual_root.global_transform = xf
	var owners: PackedInt32Array = fa["own"]
	replay_owners = owners
	var dxa: Dictionary = fa.get("dx", {})
	var dxb: Dictionary = fb.get("dx", {})
	for ci in comps.size():
		var vis: Node3D = comps[ci]["visual"]
		var ow := owners[ci]
		if ow < 0:
			vis.transform = Transform3D()
			vis.visible = true
		elif dxa.has(ow):
			var d1: Transform3D = dxa[ow]
			var d2: Transform3D = dxb.get(ow, d1)
			var center: Vector3 = comps[ow]["center"]
			vis.global_transform = d1.interpolate_with(d2, a) * Transform3D(Basis(), -center)
			vis.visible = true
		else:
			vis.visible = false
	var dfa: PackedFloat32Array = fa["defl"]
	var dfb: PackedFloat32Array = fb["defl"]
	for i in surfaces.size():
		surfaces[i]["defl"] = lerpf(dfa[i], dfb[i], a)
	var oma: PackedFloat32Array = fa["om"]
	var rfa: PackedFloat32Array = fa["rf"]
	for i in engines.size():
		(engines[i] as Propulsion).omega = lerpf(oma[i], float(fb["om"][i]), a)
		(engines[i] as Propulsion).rpm_frac = lerpf(rfa[i], float(fb["rf"][i]), a)
		if fa.has("eh"):
			engines[i].health = fa["eh"][i]
			engines[i].thr_cmd = lerpf(fa["et"][i], fb["et"][i], a)
			engines[i].running = bool(fa["er"][i])
	var wha: PackedFloat32Array = fa["wh"]
	for i in wheels.size():
		wheels[i]["comp_now"] = wha[i * 3]
		wheels[i]["spin_rate"] = wha[i * 3 + 1]
		wheels[i]["steer_now"] = wha[i * 3 + 2]
		if fa.has("wc"): wheels[i]["contact"] = bool(fa["wc"][i])
		if fa.has("wsurface"): wheels[i]["surface"] = int(fa["wsurface"][i])
	gear_pos = float(fa["gear"])
	var dmg: PackedFloat32Array = fa["dmg"]
	for ci in comps.size():
		comps[ci]["dmg_vis"] = dmg[ci]
		if fa.has("dirt"): comps[ci]["dirt"] = float(fa["dirt"][ci])
	if fa.has("pa"):
		for i in prop_angle.size(): prop_angle[i] = lerp_angle(fa["pa"][i], fb["pa"][i], a)
		for i in wheel_spin_angle.size(): wheel_spin_angle[i] = lerp_angle(fa["wa"][i], fb["wa"][i], a)
	airspeed = lerpf(float(fa.get("speed", 0.0)), float(fb.get("speed", 0.0)), a)
	scrape_level = float(fa.get("scrape", 0.0))
	on_ground = bool(fa.get("ground", false))
	in_throttle = float(fa.get("throttle", 0.0))
	_animate(0.0 if fa.has("pa") else maxf(delta, 0.0))

static func contact_tangent(relative_velocity: Vector3, normal: Vector3) -> Vector3:
	var unit := normal.normalized()
	return relative_velocity - unit * relative_velocity.dot(unit)
