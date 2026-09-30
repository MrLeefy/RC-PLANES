class_name NPC
extends RigidBody3D
## Club member. Walks between pit waypoints, keeps clear of low, fast aircraft,
## and has a real collision capsule. On impact it is knocked over by a restrained
## single-body ragdoll (no gore), then gets back up.

var waypoints: Array = []
var target := Vector3.ZERO
var speed := 1.1
var idle_t := 0.0
var down := false
var down_t := 0.0
var home_basis := Basis()
var legs: Array = []
var arms: Array = []
var body_vis: Node3D
var phase := 0.0
var pose := "walk"      # walk / stand / watch
var watch_target: Node3D = null
var rng := RandomNumberGenerator.new()
var rec_xf := Transform3D()

func setup(seed_i: int, pts: Array, start: Vector3) -> void:
	rng.seed = seed_i
	waypoints = pts
	collision_layer = Game.L_NPC
	collision_mask = Game.L_WORLD | Game.L_AIRCRAFT | Game.L_DEBRIS
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	mass = 75.0
	can_sleep = true
	lock_rotation = false
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.05
	physics_material_override = pm
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.24
	cap.height = 1.76
	cs.shape = cap
	cs.position = Vector3(0, 0.88, 0)
	add_child(cs)
	set_meta("kind", "person")
	set_meta("hardness", 0.55)
	_build_visual()
	global_position = start
	target = start
	speed = rng.randf_range(0.8, 1.3)

func _build_visual() -> void:
	body_vis = Node3D.new()
	add_child(body_vis)
	var shirt := Color.from_hsv(rng.randf(), rng.randf_range(0.25, 0.7), rng.randf_range(0.35, 0.85))
	var pants = [Color(0.15, 0.18, 0.28), Color(0.3, 0.26, 0.2), Color(0.12, 0.12, 0.13), Color(0.4, 0.38, 0.33)][rng.randi() % 4]
	var skin = [Color(0.92, 0.75, 0.62), Color(0.72, 0.52, 0.38), Color(0.45, 0.3, 0.2), Color(0.85, 0.65, 0.5)][rng.randi() % 4]
	var hair_c = [Color(0.1, 0.07, 0.05), Color(0.32, 0.2, 0.1), Color(0.62, 0.5, 0.3), Color(0.55, 0.55, 0.56), Color(0.04, 0.04, 0.05)][rng.randi() % 5]
	var shoe_c = [Color(0.06, 0.06, 0.07), Color(0.25, 0.17, 0.1), Color(0.8, 0.8, 0.8)][rng.randi() % 3]
	var hat := rng.randf() < 0.6
	var short_sleeve := rng.randf() < 0.55
	var sc := func(c: Color) -> Callable: return MeshKit.const_color(c.srgb_to_linear())
	var mk := MeshKit.new()
	# torso: chest + abdomen + hips read as a tapered body instead of a single egg
	mk.add_ellipsoid(Vector3(0, 1.30, 0), Vector3(0.20, 0.20, 0.125), 14, 8, sc.call(shirt))
	mk.add_ellipsoid(Vector3(0, 1.12, 0.003), Vector3(0.175, 0.17, 0.115), 14, 8, sc.call(shirt))
	mk.add_ellipsoid(Vector3(0, 0.97, 0), Vector3(0.175, 0.10, 0.12), 14, 6, sc.call(pants))
	mk.add_cylinder(Vector3(0, 1.03, 0), Vector3(0, 1.06, 0), 0.172, 0.172, 14, sc.call(Color(0.12, 0.09, 0.06)), false)   # belt
	mk.add_ellipsoid(Vector3(-0.21, 1.46, 0), Vector3(0.07, 0.07, 0.07), 8, 6, sc.call(shirt))       # shoulders
	mk.add_ellipsoid(Vector3(0.21, 1.46, 0), Vector3(0.07, 0.07, 0.07), 8, 6, sc.call(shirt))
	# neck + head
	mk.add_cylinder(Vector3(0, 1.46, 0), Vector3(0, 1.57, 0.005), 0.052, 0.046, 10, sc.call(skin), false)
	mk.add_ellipsoid(Vector3(0, 1.655, 0.005), Vector3(0.088, 0.112, 0.1), 14, 10, sc.call(skin))
	mk.add_ellipsoid(Vector3(0, 1.625, -0.095), Vector3(0.016, 0.02, 0.022), 6, 4, sc.call(skin.darkened(0.06)))   # nose
	mk.add_ellipsoid(Vector3(-0.035, 1.675, -0.088), Vector3(0.011, 0.008, 0.006), 6, 4, sc.call(Color(0.05, 0.05, 0.06)))  # eyes
	mk.add_ellipsoid(Vector3(0.035, 1.675, -0.088), Vector3(0.011, 0.008, 0.006), 6, 4, sc.call(Color(0.05, 0.05, 0.06)))
	mk.add_ellipsoid(Vector3(0, 1.635, 0.015), Vector3(0.091, 0.098, 0.104), 14, 8, sc.call(hair_c))                     # hair cap (back/top)
	mk.add_ellipsoid(Vector3(-0.088, 1.65, 0.005), Vector3(0.014, 0.03, 0.024), 6, 4, sc.call(skin))                     # ears
	mk.add_ellipsoid(Vector3(0.088, 1.65, 0.005), Vector3(0.014, 0.03, 0.024), 6, 4, sc.call(skin))
	if hat:
		var hc := Color.from_hsv(rng.randf(), 0.55, rng.randf_range(0.2, 0.85))
		mk.add_ellipsoid(Vector3(0, 1.715, 0.005), Vector3(0.097, 0.062, 0.105), 14, 6, sc.call(hc))
		# cap peak
		mk.add_ellipsoid(Vector3(0, 1.692, -0.108), Vector3(0.075, 0.008, 0.06), 10, 4, sc.call(hc))
	var mesh := ArrayMesh.new()
	mk.append_to(mesh, MatLib.vcol(0.82))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body_vis.add_child(mi)
	for side in [-1, 1]:
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.095, 0.92, 0)
		body_vis.add_child(leg)
		var lk := MeshKit.new()
		lk.add_cylinder(Vector3(0, 0, 0), Vector3(0, -0.45, 0.004), 0.082, 0.062, 10, sc.call(pants), false)
		lk.add_ellipsoid(Vector3(0, -0.45, 0.004), Vector3(0.063, 0.063, 0.063), 8, 6, sc.call(pants))
		lk.add_cylinder(Vector3(0, -0.45, 0.004), Vector3(0, -0.83, 0), 0.062, 0.05, 10, sc.call(pants), false)
		lk.add_ellipsoid(Vector3(0, -0.865, -0.045), Vector3(0.056, 0.042, 0.125), 10, 6, sc.call(shoe_c))
		var lm := ArrayMesh.new()
		lk.append_to(lm, MatLib.vcol(0.8))
		var lmi := MeshInstance3D.new()
		lmi.mesh = lm
		leg.add_child(lmi)
		legs.append(leg)
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.255, 1.46, 0)
		body_vis.add_child(arm)
		var ak := MeshKit.new()
		ak.add_cylinder(Vector3(0, 0, 0), Vector3(0, -0.29, 0), 0.058, 0.05, 10, sc.call(shirt), false)
		var fore: Color = skin if short_sleeve else shirt
		ak.add_ellipsoid(Vector3(0, -0.29, 0), Vector3(0.05, 0.05, 0.05), 8, 6, sc.call(fore))
		ak.add_cylinder(Vector3(0, -0.29, 0), Vector3(0, -0.53, -0.015), 0.048, 0.04, 10, sc.call(fore), false)
		ak.add_ellipsoid(Vector3(0, -0.585, -0.02), Vector3(0.04, 0.058, 0.032), 8, 6, sc.call(skin))
		var am := ArrayMesh.new()
		ak.append_to(am, MatLib.vcol(0.8))
		var ami := MeshInstance3D.new()
		ami.mesh = am
		arm.add_child(ami)
		arms.append(arm)

func _physics_process(delta: float) -> void:
	if down:
		down_t += delta
		if down_t > 4.5 and linear_velocity.length() < 0.3:
			_get_up()
		return
	var pos := global_position
	var danger := _danger()
	if danger != Vector3.ZERO:
		# step away from the aircraft's path
		var flee := danger * 3.5
		pos += flee * delta
		pose = "walk"
		phase += delta * 9.0
		_face(flee)
	elif idle_t > 0.0:
		idle_t -= delta
		pose = "watch"
		if Game.flight and Game.flight.aircraft:
			_face((Game.flight.aircraft.global_position - pos) * Vector3(1, 0, 1))
	else:
		var to := (target - pos) * Vector3(1, 0, 1)
		if to.length() < 0.3:
			idle_t = rng.randf_range(4.0, 14.0)
			if waypoints.size() > 0:
				target = waypoints[rng.randi() % waypoints.size()]
		else:
			pos += to.normalized() * speed * delta
			phase += delta * speed * 5.5
			pose = "walk"
			_face(to)
	if Game.field:
		pos.y = Game.field.ground_y(pos)
	global_position = pos
	_animate()

func _danger() -> Vector3:
	if not Game.flight or not Game.flight.aircraft:
		return Vector3.ZERO
	var ac: Node3D = Game.flight.aircraft
	var rel := global_position - ac.global_position
	var v: Vector3 = ac.linear_velocity
	if ac.global_position.y - global_position.y > 6.0 or v.length() < 3.0:
		return Vector3.ZERO
	var d := rel.length()
	if d > 25.0:
		return Vector3.ZERO
	var closing := v.dot(rel.normalized())
	if closing < 2.0 and d > 5.0:
		return Vector3.ZERO
	var side := v.cross(Vector3.UP).normalized()
	if side.dot(rel) < 0.0:
		side = -side
	return side

func _face(dir: Vector3) -> void:
	if dir.length() < 0.01:
		return
	var yaw := atan2(dir.x, dir.z)
	body_vis.rotation.y = lerp_angle(body_vis.rotation.y, yaw + PI, 0.15)

func _animate() -> void:
	var sw := sin(phase) * (0.55 if pose == "walk" else 0.0)
	for i in legs.size():
		(legs[i] as Node3D).rotation.x = sw * (1.0 if i == 0 else -1.0)
		(arms[i] as Node3D).rotation.x = -sw * 0.8 * (1.0 if i == 0 else -1.0)
	if pose == "watch":
		(arms[1] as Node3D).rotation.x = lerpf((arms[1] as Node3D).rotation.x, -0.9, 0.1)

## Called by aircraft/debris contacts.
func knock(impulse: Vector3, at: Vector3) -> void:
	if down:
		apply_impulse(impulse * 0.3, at - global_position)
		return
	if impulse.length() < 25.0:
		return
	down = true
	down_t = 0.0
	home_basis = global_transform.basis
	freeze = false
	lock_rotation = false
	angular_damp = 2.5
	linear_damp = 0.8
	apply_impulse(impulse.limit_length(300.0) * 0.6 + Vector3(0, 40, 0), at - global_position + Vector3(0, 0.6, 0))
	if Game.fx:
		Game.fx.impact_sound(at, "person", 0.6)
	if Diag:
		Diag.log_event("npc knocked")

func _get_up() -> void:
	down = false
	freeze = true
	var p := global_position
	if Game.field:
		p.y = Game.field.ground_y(p)
	global_transform = Transform3D(Basis(), p)
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	idle_t = 3.0

func reset_to(p: Vector3) -> void:
	down = false
	freeze = true
	global_transform = Transform3D(Basis(), p)
