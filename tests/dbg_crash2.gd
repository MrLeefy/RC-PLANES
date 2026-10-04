extends "res://tests/test_runner.gd"
func _run_all() -> void:
	Game.rng.seed = 1003
	await _spawn("vortex540")
	ac.continuous_cd = false
	ac.place(Transform3D(Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3.RIGHT, deg_to_rad(-40.0)), Vector3(-30, 7, -30)), 30.0)
	for i in 300:
		await get_tree().physics_frame
		if i in [50, 100, 200, 299]:
			print("--- frame ", i)
			for rb in ac.active_debris():
				var r := rb as RigidBody3D
				print("  %s pos=%s v=%s sleeping=%s cd=%s mass=%.2f layer=%d mask=%d" % [r.name, r.global_position.snapped(Vector3(0.1,0.1,0.1)), r.linear_velocity.snapped(Vector3(0.1,0.1,0.1)), r.sleeping, r.continuous_cd, r.mass, r.collision_layer, r.collision_mask])
func _report() -> void:
	pass
