extends SceneTree
## Real engine renders of the baked fleet; no generated or retouched imagery.
var views: Array[SubViewport] = []
var ids: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1920, 1360)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	DirAccess.make_dir_recursive_absolute("res://build/aircraft-gallery")
	var bg := ColorRect.new()
	bg.color = Color("101724")
	bg.size = Vector2(1920, 1360)
	root.add_child(bg)
	var title := Label.new()
	title.text = "RC PARK  |  Premade aircraft fleet — RCBeam baseline"
	title.position = Vector2(24, 12)
	title.add_theme_font_size_override("font_size", 28)
	root.add_child(title)
	var index := 0
	for definition in AircraftDB.all():
		var id := String(definition["id"])
		ids.append(id)
		var container := TextureRect.new()
		container.position = Vector2((index % 4) * 480, 64 + (index / 4) * 316)
		container.size = Vector2(480, 280)
		container.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		container.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		root.add_child(container)
		var view := SubViewport.new()
		view.size = Vector2i(960, 560)
		view.own_world_3d = true
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		view.msaa_3d = Viewport.MSAA_4X
		root.add_child(view)
		var model := load("res://assets/aircraft_baked/%s.scn" % id).instantiate() as Node3D
		view.add_child(model)
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.background_mode = Environment.BG_COLOR
		environment.environment.background_color = Color("162131")
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color("d9e7ff")
		environment.environment.ambient_light_energy = 0.65
		view.add_child(environment)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-45, -40, 0)
		light.light_energy = 1.6
		view.add_child(light)
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = Vector3(25, 130, 0)
		fill.light_energy = 0.6
		view.add_child(fill)
		var camera := Camera3D.new()
		view.add_child(camera)
		var span := 0.0
		for wing in definition["wings"]:
			span = maxf(span, float(wing["span"]))
		var length := float(definition["length"])
		var center := Vector3(0, 0, length * 0.48)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = maxf(span * 0.74, length * 1.05)
		camera.position = center + Vector3(1.0, 0.65, -1.0).normalized() * maxf(span, length) * 2.5
		camera.look_at(center)
		camera.current = true
		var label := Label.new()
		label.text = String(definition["name"])
		label.position = container.position + Vector2(18, 280)
		label.add_theme_font_size_override("font_size", 21)
		root.add_child(label)
		for frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var rendered := view.get_texture().get_image()
		rendered.save_png("res://build/aircraft-gallery/%s.png" % id)
		container.texture = ImageTexture.create_from_image(rendered)
		view.free()
		index += 1
	for frame in 12:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/aircraft-gallery/fleet.png")
	print("Rendered 16 baked aircraft to build/aircraft-gallery")
	quit()
