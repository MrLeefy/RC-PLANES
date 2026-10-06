extends Node
## Visual QA: boots the real game, drives it, and saves screenshots.
var main: Node
var outdir := "/tmp/shots/"
func _ready():
	var args := OS.get_cmdline_user_args()
	var plan := args[0] if args.size() > 0 else "menu"
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var t0 := Time.get_ticks_msec()
	while main.state != "menu":
		await get_tree().process_frame
		if Time.get_ticks_msec() - t0 > 600000:
			print("TIMEOUT boot"); get_tree().quit(); return
	print("boot ms ", Time.get_ticks_msec() - t0)
	await _frames(8)
	for step in plan.split(","):
		await _do(step)
	get_tree().quit()

func _frames(n):
	for i in n:
		await get_tree().process_frame

func _shot(name):
	await RenderingServer.frame_post_draw
	print("STATS %s draws=%d prims=%d objs=%d" % [name, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)])
	var img := get_viewport().get_texture().get_image()
	img.save_png(outdir + name + ".png")
	print("shot ", name)

func _do(step: String):
	var parts := step.split(":")
	var cmd := parts[0]
	match cmd:
		"menu":
			await _frames(4); await _shot("menu")
		"select":
			main.menu.select(parts[1])
			var tw0 := Time.get_ticks_msec()
			while (main.display_ac == null or not is_instance_valid(main.display_ac) or not main.display_ac.visible or String(main.display_ac.def["id"]) != parts[1]) and Time.get_ticks_msec() - tw0 < 120000:
				await get_tree().process_frame
			await _frames(6)
			if main.menu: main.menu.visible = false
			await _shot("hangar_" + parts[1])
			if main.menu: main.menu.visible = true
		"time":
			Settings.s("environment", "time", parts[1]); main.field.set_time_of_day(parts[1]); await _frames(4)
		"fly":
			if parts.size() > 2:
				Settings.data["last_mode"] = parts[2]
			main.menu.select(parts[1]); await _frames(2)
			main._start_flight(); await _frames(10); await _shot("fly_" + parts[1])
		"throttle":
			main.flight.set_throttle(float(parts[1]))
		"wait":
			await _frames(int(parts[1]))
		"cam":
			main.cam.set_mode(parts[1]); main.flight.flight_cam_mode = parts[1]; await _frames(6)
		"shot":
			await _shot(parts[1])
		"orbit":
			main.cam.orbit_yaw = deg_to_rad(float(parts[1])); main.cam.orbit_pitch = deg_to_rad(float(parts[2])); main.cam.orbit_dist = float(parts[3]); await _frames(6)
		"place":
			var ac = main.flight.aircraft
			var yaw := deg_to_rad(float(parts[5])) if parts.size() > 5 else -PI * 0.5
			var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(float(parts[4]))), Vector3(float(parts[1]), float(parts[2]), float(parts[3])))
			ac.place(xf, float(parts[6]) if parts.size() > 6 else 20.0)
			for e in ac.engines:
				e.running = true
			await _frames(1)
		"inputs":
			main.flight.hud.sticks.sticks[1]["val"] = Vector2(float(parts[1]), float(parts[2]))
		"state":
			print("STATE ", main.flight.state, " crashed=", main.flight.aircraft.crashed_flag, " pos=", main.flight.aircraft.global_position, " parts lost=", main.flight.parts_lost)
		"skip":
			main.flight._on_kill("skip", 0.0); await _frames(3)
		"repair":
			main.flight._on_kill("repair", 0.0); await _frames(5)
		"autofly":
			# simple autopilot: climb out and circle the field for N frames, shots at intervals
			var n := int(parts[1])
			var ac = main.flight.aircraft
			main.flight.set_throttle(0.85)
			for i in n:
				var B: Basis = ac.global_transform.basis
				var bank := atan2(-B.x.y, B.y.y)
				var pitch := asin(clampf(-B.z.y, -1, 1))
				var alt: float = ac.global_position.y
				var tb := 0.0 if alt < 12.0 else deg_to_rad(-35.0)
				var tp := deg_to_rad(12.0) if alt < 25.0 else deg_to_rad(2.0)
				if ac.airspeed < 8.0 and alt < 1.0:
					tp = 0.0
				var w_l: Vector3 = B.transposed() * ac.angular_velocity
				var r := clampf((tb - bank) * 1.5 - (-w_l.z) * 0.2, -1, 1)
				var p := clampf((tp - pitch) * 2.5 - w_l.x * 0.3, -1, 1)
				main.flight.hud.sticks.sticks[1]["val"] = Vector2(r, p)
				await get_tree().process_frame
				if parts.size() > 2 and i > 0 and i % int(parts[2]) == 0:
					await _shot("auto_%d" % i)
		"hud":
			main.flight._on_hud(parts[1]); await _frames(int(parts[2]) if parts.size() > 2 else 20)
		"killact":
			main.flight._on_kill(parts[1], float(parts[2]) if parts.size() > 2 else 0.0); await _frames(20)
		"pauseact":
			main.flight._on_pause(parts[1]); await _frames(10)
		"closesettings":
			if main.settings_ui: main.settings_ui._close()
			await _frames(5)
		"tab":
			if main.settings_ui: main.settings_ui.tabs.current_tab = int(parts[1])
			await _frames(5)
		"dbg":
			for c in main.menu.get_children():
				print(c.name, " pos=", c.position, " size=", c.size, " vis=", c.visible)
			print("menu size ", main.menu.size, " safe ", DisplayServer.get_display_safe_area(), " win ", DisplayServer.window_get_size())
		"camfixed":
			main.cam.target = null
			main.cam.global_position = Vector3(float(parts[1]), float(parts[2]), float(parts[3]))
			main.cam.look_at(Vector3(float(parts[4]), float(parts[5]), float(parts[6])))
			main.cam.fov = float(parts[7]) if parts.size() > 7 else 60.0
			await _frames(4)
