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