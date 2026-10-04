extends "res://tests/test_runner.gd"
func _run_all() -> void:
	var tele := 0
	var dteleport := 0
	var crashes := 0
	var n := 24
	for k in n:
		Game.rng.seed = 1000 + k
		await _spawn("vortex540")
		if OS.get_environment("NOCCD") != "": ac.continuous_cd = false
		ac.place(Transform3D(Basis(Vector3.UP, -PI * 0.5) * Basis(Vector3.RIGHT, deg_to_rad(-40.0)), Vector3(-30, 7, float(OS.get_environment("DZ") if OS.get_environment("DZ") != "" else "-30"))), 30.0)
		var jumped := false
		var last := ac.global_position
		for i in 300:
			await get_tree().physics_frame
			if ac.global_position.distance_to(last) > 20.0: jumped = true
			last = ac.global_position
			for rb in ac.active_debris():
				if (rb as RigidBody3D).global_position.length() > 3000.0 or (rb as RigidBody3D).global_position.y < -20.0: dteleport += 1
		if jumped: tele += 1
		if ac.crashed_flag: crashes += 1
	print("RESULT teleports=%d/%d crashed=%d/%d debris_teleport_frames=%d" % [tele, n, crashes, n, dteleport])
func _report() -> void:
	pass
