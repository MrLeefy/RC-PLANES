extends RigidBody3D
## Detached aircraft structure. Real rigid body: inherits momentum, tumbles,
## collides, and can break again on secondary impacts (split from the pool).

var aircraft: Node = null
var active := false
var t_active := 0.0
var last_hit := 0.0
var exception_body: PhysicsBody3D
var exception_remaining := 0.0
var exception_mutual := false

func activate() -> void:
	active = true
	t_active = 0.0
	last_hit = 0.0

func _physics_process(delta: float) -> void:
	if exception_remaining > 0.0:
		exception_remaining -= delta
		if exception_remaining <= 0.0:
			clear_temporary_exceptions()
	if not active or freeze:
		return
	t_active += delta
	if global_position.y < -30.0:
		freeze = true
		active = false

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if not active:
		return
	# Thin pieces move several cm per physics step; with CCD off (Jolt's sweep teleports them) a hard
	# ground hit could skip through the heightfield. Keep them on the right side of the terrain.
	var p := state.transform.origin
	if is_instance_valid(Game.field) and absf(p.x) < Field.HALF and absf(p.z) < Field.HALF:
		var gy: float = Game.field.ground_y(p)
		if p.y < gy - 0.03:
			var t := state.transform
			t.origin.y = gy + 0.03
			state.transform = t
			var v := state.linear_velocity
			if v.y < 0.0:
				v.y = -v.y * 0.2
				v.x *= 0.7
				v.z *= 0.7
				state.linear_velocity = v
	var n := state.get_contact_count()
	for i in n:
		var nrm := state.get_contact_local_normal(i)
		var v_rel := state.get_contact_local_velocity_at_position(i) - state.get_contact_collider_velocity_at_position(i)
		var closing := maxf(-v_rel.dot(nrm), 0.0)
		var J := state.get_contact_impulse(i).length()
		var sev := maxf(closing, J / maxf(mass, 0.05))
		var pos := state.get_contact_collider_position(i)
		var col := state.get_contact_collider_object(i)
		if col and col is Object and (col as Object).has_method("knock") and sev > 2.0:
			(col as Object).call_deferred("knock", -nrm * sev * mass, pos)
		if sev > 2.5 and t_active - last_hit > 0.12:
			last_hit = t_active
			if Game.fx:
				Game.fx.call_deferred("debris_hit", pos, sev, mass)
			var members: Array = get_meta("members", [])
			if sev > 7.5 and members.size() > 1 and aircraft and is_instance_valid(aircraft) and aircraft.damage_mode == "physical":
				aircraft.call_deferred("split_debris", self, sev)

func ignore_temporarily(body: PhysicsBody3D, seconds: float, mutual: bool) -> void:
	clear_temporary_exceptions()
	exception_body = body
	exception_remaining = seconds
	exception_mutual = mutual
	add_collision_exception_with(body)
	if mutual: body.add_collision_exception_with(self)

func clear_temporary_exceptions() -> void:
	if is_instance_valid(exception_body):
		remove_collision_exception_with(exception_body)
		if exception_mutual: exception_body.remove_collision_exception_with(self)
	exception_body = null
	exception_remaining = 0.0
	exception_mutual = false
