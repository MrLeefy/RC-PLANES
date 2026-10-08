extends Node3D
## Model QA turntable: renders each aircraft from several fixed views on a neutral stage (no field),
## so model defects are quick to inspect. Run (software Vulkan):
##   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a godot --path . \
##     --rendering-driver vulkan --resolution 1280x720 res://tests/turntable.tscn -- <id|all> [views] [outdir]
## views: comma list of  q (3/4 front) s (side) t (top) f (front) r (rear 3/4) n (nose close) u (underside) g (gear up, q view)
##   os / ot / of: orthographic black-on-white silhouettes (side, plan, front) at a known scale, for overlaying on
##   real three-view drawings; each also writes <id>_<view>.json with pixels-per-metre and the world point at the image centre
var ac: Aircraft
var cam: Camera3D
var outdir := "/tmp/tt/"
var detail := 2

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var only := args[0] if args.size() > 0 else "all"
	var views := (args[1] if args.size() > 1 else "q,s,t,f").split(",")
	if args.size() > 2:
		outdir = args[2]
	if args.size() > 3:
		detail = int(args[3])
	DirAccess.make_dir_recursive_absolute(outdir)
	get_window().size = Vector2i(1280, 720)
	_stage()
	await get_tree().process_frame
	var ids := AircraftDB.ids() if only == "all" else PackedStringArray(only.split(","))
	for id in ids:
		_spawn(id)
		for v in views:
			await _view(id, v)
	get_tree().quit()

func _stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pm := ProceduralSkyMaterial.new()
	pm.sky_top_color = Color(0.32, 0.5, 0.78)
	pm.sky_horizon_color = Color(0.7, 0.8, 0.9)
	pm.ground_horizon_color = Color(0.6, 0.62, 0.6)
	pm.ground_bottom_color = Color(0.35, 0.37, 0.35)
	sky.sky_material = pm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 1.25
	# TT_NOSHADOW=1 renders without the sun's shadow map, to tell lighting artefacts from model defects
	sun.shadow_enabled = OS.get_environment("TT_NOSHADOW") != "1"
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pl := PlaneMesh.new()
	pl.size = Vector2(60, 60)
	ground.mesh = pl
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.24, 0.25, 0.26)
	gm.roughness = 0.95
	ground.material_override = gm
	add_child(ground)
	# TT_LOD0=1 forces the finest mesh level (mesh_lod_threshold 0), to tell LOD choice from geometry
	if OS.get_environment("TT_LOD0") == "1":
		get_viewport().mesh_lod_threshold = 0.0
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	add_child(cam)

func _spawn(id: String) -> void:
	if ac:
		ac.queue_free()
	ac = Aircraft.new()
	ac.setup(AircraftDB.by_id(id), Settings.aircraft_cfg(id), detail, true)
	add_child(ac)
	# TT_PLAIN=1 swaps the aircraft shader for plain vertex-colour albedo, to tell shading from geometry
	if OS.get_environment("TT_PLAIN") == "1":
		var stack: Array = [ac]
		while stack.size() > 0:
			var nd: Node = stack.pop_back()
			stack.append_array(nd.get_children())
			if nd is MeshInstance3D:
				(nd as MeshInstance3D).material_override = MatLib.vcol(0.6, 0.0)
	var low := 0.0
	for w in ac.wheels:
		low = minf(low, (w["center"] as Vector3).y - float(w["r"]))
	var b := Basis(Vector3.UP, 0.0)
	if String(ac.def["gear"]["type"]) == "taildragger":
		var main: Dictionary = ac.wheels[0]
		var tail: Dictionary = ac.wheels[ac.wheels.size() - 1]
		var ang := atan2((tail["center"].y - tail["r"]) - (main["center"].y - main["r"]), tail["center"].z - main["center"].z)
		b = Basis(Vector3.RIGHT, ang)
		low = 0.0
		for w in ac.wheels:
			low = minf(low, (b * ((w["center"] as Vector3) - Vector3(0, float(w["r"]), 0))).y)
	ac.global_transform = Transform3D(b, Vector3(0, -low + 0.01, 0))
	ac.gear_pos = 1.0
	ac.update_visuals(ac.global_transform, 0.0)

func _silhouette(id: String, v: String) -> void:
	var L := ac.length_m
	var S := ac.span
	# level flight attitude, not the tail-down ground stance the other views use
	var rest_xf := ac.global_transform
	ac.global_transform = Transform3D(Basis(), Vector3(0, 1.0, 0))
	ac.update_visuals(ac.global_transform, 0.0)
	var low := 0.0
	var high := 0.0
	var stack: Array = [ac]
	var saved: Array = []
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color.BLACK
	black.cull_mode = BaseMaterial3D.CULL_DISABLED
	while stack.size() > 0:
		var nd: Node = stack.pop_back()
		stack.append_array(nd.get_children())
		if nd is MeshInstance3D:
			var mi := nd as MeshInstance3D
			saved.append([mi, mi.material_override, mi.cast_shadow])
			mi.material_override = black
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var bb := mi.global_transform * mi.get_aabb()
			low = minf(low, bb.position.y)
			high = maxf(high, bb.end.y)
	var env := (get_children().filter(func(c): return c is WorldEnvironment)[0] as WorldEnvironment).environment
	var old_bg := env.background_mode
	var old_amb := env.ambient_light_source
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.WHITE
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	for c in get_children():
		if c is MeshInstance3D and c != ac:
			c.visible = false
		if c is DirectionalLight3D:
			c.visible = false
	var vw := float(get_window().size.x)
	var vh := float(get_window().size.y)
	var height := high - low
	var need_h := L if v == "os" else S
	var need_v := (L if v == "ot" else height)
	var width := maxf(need_h, need_v * vw / vh) * 1.1
	var ppm := vw / width
	var ctr := Vector3(0.0, (low + high) * 0.5, L * 0.5)
	match v:
		"os":
			cam.global_position = ctr + Vector3(-50, 0, 0)
			cam.look_at(ctr, Vector3.UP)
		"ot":
			cam.global_position = ctr + Vector3(0, 50, 0)
			cam.look_at(ctr, Vector3(0, 0, -1))
		"of":
			cam.global_position = ctr + Vector3(0, 0, -50)
			cam.look_at(ctr, Vector3.UP)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = width
	cam.near = 0.05
	cam.far = 200.0
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s%s_%s.png" % [outdir, id, v])
	# screen right is +Z (side: nose on the left), +X (plan: nose at the top) or -X (front, seen from ahead)
	var meta := {"id": id, "view": v, "px_per_m": ppm, "image_w": vw, "image_h": vh, "span_m": S, "length_m": L,
		"center_world": [ctr.x, ctr.y, ctr.z], "note": "side: right=+z (tail), up=+y; plan: right=+x, up=-z (nose at top); front: right=-x, up=+y; nose at z=0"}
	var f := FileAccess.open("%s%s_%s.json" % [outdir, id, v], FileAccess.WRITE)
	f.store_string(JSON.stringify(meta))
	f.close()
	for e in saved:
		(e[0] as MeshInstance3D).material_override = e[1]
		(e[0] as MeshInstance3D).cast_shadow = e[2]
	env.background_mode = old_bg
	env.ambient_light_source = old_amb
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	for c in get_children():
		if c is MeshInstance3D or c is DirectionalLight3D:
			c.visible = true
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	ac.global_transform = rest_xf
	ac.update_visuals(ac.global_transform, 0.0)

func _view(id: String, v: String) -> void:
	if v in ["os", "ot", "of"]:
		await _silhouette(id, v)
		return
	var L := ac.length_m
	var S := ac.span
	var ctr := ac.global_transform * Vector3(0, 0.0, L * 0.5)
	ctr.y = maxf(ctr.y, 0.1) + 0.05
	var R := maxf(L, S) * 1.3 + 0.2
	var from := ctr
	var look := ctr
	match v:
		"q": from = ctr + Vector3(-0.75, 0.38, -0.85).normalized() * R * 1.1
		"s": from = ctr + Vector3(-1, 0.1, 0) * R * 1.0
		"t":
			from = ctr + Vector3(0, 1, 0.001) * R * 1.15
		"f": from = ctr + Vector3(0, 0.12, -1) * R * 1.2
		"r": from = ctr + Vector3(0.7, 0.35, 0.9).normalized() * R * 1.1
		"n":
			look = ac.global_transform * Vector3(0, 0.02, L * 0.12)
			from = look + Vector3(-0.6, 0.25, -0.75).normalized() * maxf(L, S) * 0.42
		"u":
			from = ctr + Vector3(-0.45, -0.1, -0.8).normalized() * R * 1.1
			from.y = 0.05
		"g":
			ac.gear_pos = 0.0
			ac.update_visuals(ac.global_transform, 0.0)
			from = ctr + Vector3(-0.75, -0.05, -0.85).normalized() * R * 1.1
			from.y = 0.12
	cam.global_position = from
	cam.look_at(look if v == "n" else ctr, Vector3.UP if v != "t" else Vector3(0, 0, -1))
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s%s_%s.png" % [outdir, id, v])
	if v == "g":
		ac.gear_pos = 1.0
