class_name Field
extends Node3D
## The RC Park flying field. Built procedurally at load time, with every visible
## substantial object backed by a cheap collision proxy (boxes/capsules/heightfield)
## and foliage represented by soft drag volumes instead of rigid leaves.
##
## Layout (metres): runway along X centred at origin (140 x 12), grass strip north,
## pilot line / safety fence at z=16, pits z 20..40, parking z 46..70.

signal built

const HALF := 1200.0
const N := 385
const RWY_HALF_LEN := 70.0
const RWY_HALF_W := 6.0

var cell := 2.0 * HALF / float(N - 1)
var heights := PackedFloat32Array()
var hnoise := FastNoiseLite.new()
var hnoise2 := FastNoiseLite.new()
var fnoise := FastNoiseLite.new()
var rng := RandomNumberGenerator.new()

var pilot_pos := Vector3(0, 1.7, 15.2)
var runway_heading := Vector3(1, 0, 0)
var sun: DirectionalLight3D
var world_env: WorldEnvironment
var env: Environment
var sky_mat: ShaderMaterial
var terrain_mat: ShaderMaterial
var npcs: Array = []
var windsock_pivot: Node3D
var windsock_segs: Array = []
var cloud_off := Vector2.ZERO
var parked: Array = []
var grass_nodes: Array = []
var far_tree_nodes: Array = []
var near_tree_nodes: Array = []
var quality := "high"
var time_preset := "golden"
var gates: Array = []
var outer_canopies := FoliageIndex.new()

var kits: Dictionary = {}
var bodies: Dictionary = {}
var _prop_mats: Dictionary = {}

const CAT := {
	"structure": {"hard": 1.3, "kind": "structure", "surface": 3},
	"furniture": {"hard": 1.0, "kind": "furniture", "surface": 4},
	"vehicle": {"hard": 1.3, "kind": "vehicle", "surface": 5},
	"net": {"hard": 0.45, "kind": "net", "surface": 5},
	"rail": {"hard": 1.1, "kind": "fence", "surface": 4},
	"runway": {"hard": 1.1, "kind": "ground", "surface": 1},
	"pad": {"hard": 1.1, "kind": "ground", "surface": 3},
	"sign": {"hard": 1.1, "kind": "sign", "surface": 4},
	"small": {"hard": 0.9, "kind": "equipment", "surface": 5},
}

# ================================================================ build
func build_async(q: String, progress: Callable) -> void:
	quality = q
	rng.seed = 424242
	hnoise.seed = 7
	hnoise.frequency = 0.0022
	hnoise.fractal_octaves = 4
	hnoise2.seed = 99
	hnoise2.frequency = 0.0007
	fnoise.seed = 13
	fnoise.frequency = 0.004
	fnoise.fractal_octaves = 3
	progress.call(0.02, "Surveying terrain")
	await get_tree().process_frame
	_build_heights()
	_build_environment()
	progress.call(0.08, "Laying terrain")
	await get_tree().process_frame
	await _build_terrain_async(progress)
	progress.call(0.3, "Paving runway")
	await get_tree().process_frame
	_build_runway()
	_build_mountains()
	progress.call(0.36, "Building pits & clubhouse")
	await get_tree().process_frame
	_build_flightline()
	_build_pits()
	_build_clubhouse()
	_build_parking()
	_build_perimeter()
	_build_windsock()
	_build_signs()
	progress.call(0.5, "Parking club aircraft")
	await get_tree().process_frame
	_build_parked_aircraft()
	_commit_props()
	progress.call(0.58, "Planting trees")
	await get_tree().process_frame
	await _build_trees_async(progress)
	progress.call(0.82, "Growing grass")
	await get_tree().process_frame
	_build_grass()
	progress.call(0.9, "Inviting club members")
	await get_tree().process_frame
	_build_npcs()
	_build_gates()
	await SurfaceTextures.wait_ready()
	set_time_of_day(time_preset)
	apply_quality(quality)
	built.emit()

# ================================================================ heights
func h_raw(x: float, z: float) -> float:
	var ax := absf(x)
	var az := absf(z)
	var d := Vector2(maxf(ax - 240.0, 0.0), maxf(az - 170.0, 0.0)).length()
	var blend := smoothstep(0.0, 260.0, d)
	if blend <= 0.0:
		return 0.0
	var r := Vector2(x, z).length()
	var hills := (hnoise.get_noise_2d(x, z) * 0.5 + 0.5) * 48.0 + hnoise2.get_noise_2d(x, z) * 30.0
	hills += smoothstep(700.0, 1150.0, r) * (hnoise2.get_noise_2d(x * 1.7, z * 1.7) * 0.5 + 0.7) * 70.0
	return maxf(hills * blend - 2.0 * blend, -3.0)

func _build_heights() -> void:
	heights.resize(N * N)
	for j in N:
		var z := -HALF + j * cell
		for i in N:
			var x := -HALF + i * cell
			heights[j * N + i] = h_raw(x, z)

## Height of the collision surface (bilinear on the heightfield grid)
func ground_y(p: Vector3) -> float:
	var fx := (p.x + HALF) / cell
	var fz := (p.z + HALF) / cell
	var i := clampi(int(floor(fx)), 0, N - 2)
	var j := clampi(int(floor(fz)), 0, N - 2)
	var tx := clampf(fx - i, 0.0, 1.0)
	var tz := clampf(fz - j, 0.0, 1.0)
	var h00 := heights[j * N + i]
	var h10 := heights[j * N + i + 1]
	var h01 := heights[(j + 1) * N + i]
	var h11 := heights[(j + 1) * N + i + 1]
	var base := lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)
	if absf(p.x) <= RWY_HALF_LEN and absf(p.z) <= RWY_HALF_W:
		return 0.03
	if p.x > -47.0 and p.x < 32.0 and p.z > 19.0 and p.z < 41.0:
		return 0.02
	return base

func surface_at(p: Vector3) -> int:
	var x := p.x
	var z := p.z
	if absf(x) <= RWY_HALF_LEN and absf(z) <= RWY_HALF_W:
		return Game.SURF_ASPHALT
	if x > -43.5 and x < -36.5 and z > 6.0 and z < 20.0:
		return Game.SURF_DIRT
	if x > -47.0 and x < 32.0 and z > 19.0 and z < 41.0:
		return Game.SURF_CONCRETE
	if x > -52.0 and x < 32.0 and z > 44.0 and z < 72.0:
		return Game.SURF_DIRT
	if absf(x) < 200.0 and absf(z) < 110.0:
		return Game.SURF_GRASS
	return Game.SURF_TALLGRASS

# ================================================================ environment & lighting
func _build_environment() -> void:
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.12
	sun.directional_shadow_max_distance = 140.0
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 2.2
	sun.light_angular_distance = 0.6
	add_child(sun)
	world_env = WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.55
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.4
	world_env.environment = env
	add_child(world_env)

const PRESETS := {
	"morning": {"sun_el": 16.0, "sun_az": 110.0, "sun_col": Color(1.0, 0.86, 0.7), "sun_e": 2.4, "zen": Color(0.30, 0.50, 0.82), "hor": Color(0.86, 0.84, 0.82),
		"ground": Color(0.3, 0.32, 0.28), "amb": 0.9, "fog": Color(0.78, 0.8, 0.84), "fog_d": 0.0016, "clouds": 0.35, "cloud_dark": 0.3, "exp": 1.0, "glow": 0.5, "lush": 1.0},
	"midday": {"sun_el": 62.0, "sun_az": 160.0, "sun_col": Color(1.0, 0.97, 0.92), "sun_e": 3.0, "zen": Color(0.18, 0.40, 0.80), "hor": Color(0.68, 0.78, 0.9),
		"ground": Color(0.32, 0.34, 0.3), "amb": 0.8, "fog": Color(0.72, 0.8, 0.9), "fog_d": 0.0011, "clouds": 0.42, "cloud_dark": 0.35, "exp": 0.92, "glow": 0.2, "lush": 0.9},
	"golden": {"sun_el": 7.5, "sun_az": 252.0, "sun_col": Color(1.0, 0.72, 0.42), "sun_e": 2.5, "zen": Color(0.28, 0.42, 0.72), "hor": Color(0.98, 0.78, 0.55),
		"ground": Color(0.3, 0.28, 0.22), "amb": 0.85, "fog": Color(0.92, 0.78, 0.62), "fog_d": 0.0012, "clouds": 0.4, "cloud_dark": 0.25, "exp": 1.05, "glow": 0.7, "lush": 1.0},
	"overcast": {"sun_el": 40.0, "sun_az": 200.0, "sun_col": Color(0.85, 0.87, 0.9), "sun_e": 0.8, "zen": Color(0.55, 0.58, 0.62), "hor": Color(0.72, 0.74, 0.76),
		"ground": Color(0.3, 0.31, 0.3), "amb": 1.25, "fog": Color(0.66, 0.68, 0.7), "fog_d": 0.0024, "clouds": 0.92, "cloud_dark": 0.55, "exp": 1.1, "glow": 0.0, "lush": 0.95},
}

func set_time_of_day(preset: String) -> void:
	time_preset = preset if PRESETS.has(preset) else "golden"
	var p: Dictionary = PRESETS[time_preset]
	var el := deg_to_rad(float(p["sun_el"]))
	var az := deg_to_rad(float(p["sun_az"]))
	# light points FROM sun toward the ground
	var to_sun := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	sun.look_at_from_position(Vector3.ZERO, -to_sun, Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.FORWARD)
	sun.light_color = p["sun_col"]
	sun.light_energy = float(p["sun_e"])
	sun.shadow_enabled = time_preset != "overcast" or true
	sun.shadow_opacity = 1.0 if time_preset != "overcast" else 0.45
	sky_mat.set_shader_parameter("zenith", p["zen"])
	sky_mat.set_shader_parameter("horizon", p["hor"])
	sky_mat.set_shader_parameter("ground", p["ground"])
	sky_mat.set_shader_parameter("sun_tint", p["sun_col"])
	sky_mat.set_shader_parameter("cloud_cov", p["clouds"])
	sky_mat.set_shader_parameter("cloud_dark", p["cloud_dark"])
	sky_mat.set_shader_parameter("glow", p["glow"])
	sky_mat.set_shader_parameter("sun_disc", 0.0 if time_preset == "overcast" else 1.0)
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = float(p["amb"])
	env.fog_light_color = p["fog"]
	env.fog_density = float(p["fog_d"])
	env.tonemap_exposure = float(p["exp"])
	env.glow_enabled = float(p["glow"]) > 0.05 and quality != "performance"
	env.glow_intensity = float(p["glow"]) * 0.6
	if terrain_mat:
		terrain_mat.set_shader_parameter("lushness", p["lush"])
		terrain_mat.set_shader_parameter("cloud_shadow", clampf(float(p["clouds"]) * 0.32, 0.0, 0.3))

func apply_quality(q: String) -> void:
	quality = q
	RenderingServer.global_shader_parameter_set("gfx_detail", 0.0 if q == "performance" else (2.0 if q == "ultra" else 1.0))
	match q:
		"performance":
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			sun.directional_shadow_max_distance = 70.0
			RenderingServer.directional_shadow_atlas_set_size(1024, true)
			RenderingServer.global_shader_parameter_set("grass_fade", 28.0)
			env.glow_enabled = false
			for n in far_tree_nodes:
				(n as GeometryInstance3D).visibility_range_end = 700.0
				(n as GeometryInstance3D).visibility_range_begin = 180.0
			for n in near_tree_nodes:
				(n as GeometryInstance3D).visibility_range_end = 220.0
				(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		"high":
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 140.0
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
			RenderingServer.global_shader_parameter_set("grass_fade", 50.0)
			for n in far_tree_nodes:
				(n as GeometryInstance3D).visibility_range_end = 1600.0
				(n as GeometryInstance3D).visibility_range_begin = 300.0
			for n in near_tree_nodes:
				(n as GeometryInstance3D).visibility_range_end = 340.0
				(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		"ultra":
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 220.0
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
			RenderingServer.global_shader_parameter_set("grass_fade", 75.0)
			for n in far_tree_nodes:
				(n as GeometryInstance3D).visibility_range_end = 2400.0
				(n as GeometryInstance3D).visibility_range_begin = 460.0
			for n in near_tree_nodes:
				(n as GeometryInstance3D).visibility_range_end = 500.0
				(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Complete, idempotent presets: a live transition has the same outcome as boot.
	var p: Dictionary = PRESETS.get(time_preset, PRESETS["golden"])
	env.glow_enabled = float(p["glow"]) > 0.05 and q != "performance"
	env.glow_intensity = float(p["glow"]) * 0.6
	var density := clampf(float(Settings.g("graphics", "grass", 1.0)), 0.0, 2.0)
	var quality_density := 0.4 if q == "performance" else (2.2 if q == "ultra" else 1.5)
	for g in grass_nodes:
		var mm: MultiMesh = (g as MultiMeshInstance3D).multimesh
		mm.visible_instance_count = clampi(roundi(mm.instance_count * density * quality_density / 3.2), 0, mm.instance_count)
		(g as Node3D).visible = mm.visible_instance_count > 0

## Keep the sharp shadow cascades centred on what matters: the aircraft.
func focus_shadows(near_dist: float) -> void:
	# split 1 covers the aircraft area close to the camera; far split cheap
	var md := sun.directional_shadow_max_distance
	sun.directional_shadow_split_1 = clampf((near_dist + 15.0) / md, 0.08, 0.6)

# ================================================================ terrain
func _build_terrain_async(progress: Callable) -> void:
	terrain_mat = ShaderMaterial.new()
	terrain_mat.shader = load("res://shaders/terrain.gdshader")
	# collision: one heightfield (uniform scale -> Jolt friendly)
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = Game.L_WORLD
	body.set_meta("kind", "ground")
	body.set_meta("hardness", 1.0)
	var hs := HeightMapShape3D.new()
	hs.map_width = N
	hs.map_depth = N
	var scaled := PackedFloat32Array()
	scaled.resize(heights.size())
	for i in heights.size():
		scaled[i] = heights[i] / cell
	hs.map_data = scaled
	var cs := CollisionShape3D.new()
	cs.shape = hs
	cs.scale = Vector3(cell, cell, cell)
	body.add_child(cs)
	add_child(body)
	# visual: chunked grid with index-decimated LODs
	var chunks := 8
	var per := (N - 1) / chunks
	var col := MeshKit.const_color(Color.WHITE)
	var done := 0
	for cj in chunks:
		for ci in chunks:
			var kit := MeshKit.new()
			var rows := []
			for j in range(cj * per, (cj + 1) * per + 1):
				var row := PackedVector3Array()
				for i in range(ci * per, (ci + 1) * per + 1):
					row.append(Vector3(-HALF + i * cell, heights[j * N + i], -HALF + j * cell))
				rows.append(row)
			# rows along +z, columns along +x: cross(dj=+x, di=+z) = -y -> flip normals up
			kit.add_grid(rows, false, col, true, true)
			var mesh := ArrayMesh.new()
			kit.append_to(mesh, terrain_mat, cell * 0.6, cell * 1.8)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			done += 1
		progress.call(0.08 + 0.2 * float(done) / (chunks * chunks), "Laying terrain")
		await get_tree().process_frame
	# outer skirt so the horizon never shows a hard edge
	var skirt := MeshKit.new()
	var segs := 64
	var ring_in := PackedVector3Array()
	var ring_out := PackedVector3Array()
	for k in segs:
		var a := TAU * float(k) / segs
		var d := Vector3(cos(a), 0, sin(a))
		var r0 := HALF * 0.98
		ring_in.append(d * r0 / maxf(absf(d.x), absf(d.z)) * 0.999 + Vector3(0, 30.0, 0))
		ring_out.append(d * 3500.0 + Vector3(0, 40.0, 0))
	skirt.add_grid([ring_in, ring_out], true, col, false)
	var sm := ArrayMesh.new()
	skirt.append_to(sm, terrain_mat)
	var smi := MeshInstance3D.new()
	smi.mesh = sm
	smi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(smi)

func _build_mountains() -> void:
	var kit := MeshKit.new()
	var segs := 160
	var n := FastNoiseLite.new()
	n.seed = 5
	n.frequency = 0.9
	n.fractal_octaves = 4
	var rows := [PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
	for k in segs:
		var a := TAU * float(k) / segs
		var d := Vector3(cos(a), 0, sin(a))
		var h := 120.0 + (n.get_noise_1d(a * 3.0) * 0.5 + 0.5) * 260.0
		# lower ridges in the direction the pilot looks at golden hour for a nice silhouette
		rows[0].append(d * 2600.0 + Vector3(0, 0, 0))
		rows[1].append(d * 3000.0 + Vector3(0, h * 0.8, 0))
		rows[2].append(d * 3400.0 + Vector3(0, h, 0))
	var colf := func(p: Vector3, _n: Vector3) -> Color:
		var t := clampf(p.y / 300.0, 0.0, 1.0)
		return Color(0.12, 0.17, 0.12).lerp(Color(0.2, 0.25, 0.26), t).srgb_to_linear()
	# columns around (angle increasing: x->z), rows outward & up; normals should face the centre
	kit.add_grid(rows, true, colf, false)
	var mesh := ArrayMesh.new()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	kit.append_to(mesh, m)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

# ================================================================ prop helpers
func _pmat(kind: int) -> ShaderMaterial:
	if _prop_mats.has(kind):
		return _prop_mats[kind]
	var m := ShaderMaterial.new()
	m.shader = MatLib.shader("res://shaders/props.gdshader")
	m.set_shader_parameter("kind", kind)
	_prop_mats[kind] = m
	return m

func _kit(kind: int) -> MeshKit:
	if not kits.has(kind):
		kits[kind] = MeshKit.new()
	return kits[kind]

func _body(cat: String) -> StaticBody3D:
	if bodies.has(cat):
		return bodies[cat]
	var b := StaticBody3D.new()
	b.name = "Col_" + cat
	b.collision_layer = Game.L_WORLD
	var info: Dictionary = CAT[cat]
	b.set_meta("kind", info["kind"])
	b.set_meta("hardness", info["hard"])
	b.set_meta("surface", info["surface"])
	var pm := PhysicsMaterial.new()
	pm.friction = 0.7
	pm.bounce = 0.1
	b.physics_material_override = pm
	add_child(b)
	bodies[cat] = b
	return b

func _col_box(cat: String, xf: Transform3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size.max(Vector3(0.02, 0.02, 0.02))
	cs.shape = bs
	cs.transform = xf
	_body(cat).add_child(cs)

func _col_hull(cat: String, pts: PackedVector3Array) -> void:
	var cs := CollisionShape3D.new()
	var h := ConvexPolygonShape3D.new()
	h.points = pts
	cs.shape = h
	_body(cat).add_child(cs)

func _col_cyl(cat: String, pos: Vector3, r: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	cs.shape = c
	cs.position = pos + Vector3(0, h * 0.5, 0)
	_body(cat).add_child(cs)

func _lin(c: Color) -> Color:
	return c.srgb_to_linear()

## Visual box + matching collider. pos = centre of the bottom face.
func box(pos: Vector3, size: Vector3, color: Color, kind: int, cat := "", yaw := 0.0, pitch := 0.0) -> void:
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var center := pos + b * Vector3(0, size.y * 0.5, 0)
	var xf := Transform3D(b * Basis.from_scale(size), center)
	_kit(kind).add_box(xf, _lin(color))
	if cat != "":
		_col_box(cat, Transform3D(b, center), size)

func cyl(a: Vector3, b: Vector3, r: float, color: Color, kind: int, segs := 8) -> void:
	_kit(kind).add_cylinder(a, b, r, r, segs, MeshKit.const_color(_lin(color)), true)

func _commit_props() -> void:
	for kind in kits.keys():
		var kit: MeshKit = kits[kind]
		if kit.is_empty():
			continue
		var mesh := ArrayMesh.new()
		kit.append_to(mesh, _pmat(kind))
		var mi := MeshInstance3D.new()
		mi.name = "Props_%d" % kind
		mi.mesh = mesh
		add_child(mi)
	kits.clear()

func label(text: String, pos: Vector3, yaw: float, size: float, color: Color, flat := false) -> Label3D:
	var l := Label3D.new()
	l.text = text
	# Glyph resolution scales with the physical size so a 4.5 m runway numeral is not a
	# stretched 96 px bitmap (blobby, stair-stepped edges).
	var fpx := int(clampf(size * 110.0, 96.0, 480.0))
	l.font_size = fpx
	l.pixel_size = size / float(fpx)
	l.outline_size = 0
	l.modulate = color
	l.shaded = true
	l.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	l.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	l.position = pos
	l.rotation = Vector3(-PI * 0.5 if flat else 0.0, yaw, 0)
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(l)
	return l

# ================================================================ runway & pads
func _build_runway() -> void:
	var kit := MeshKit.new()
	var rows := []
	# The slab is 3 cm proud of the grass. A vertical lip that tall stops a small nose wheel dead (a 2.6 cm
	# wheel cannot climb it), so the slab edge is bevelled over 60 cm in both the mesh and the collider.
	var bev := 0.6
	var zs := [-RWY_HALF_W - bev]
	for j in 13:
		zs.append(-RWY_HALF_W + j * (2.0 * RWY_HALF_W / 12.0))
	zs.append(RWY_HALF_W + bev)
	var xs := [-RWY_HALF_LEN - bev]
	for i in 71:
		xs.append(-RWY_HALF_LEN + i * (2.0 * RWY_HALF_LEN / 70.0))
	xs.append(RWY_HALF_LEN + bev)
	for z in zs:
		var row := PackedVector3Array()
		for x in xs:
			var outside := absf(x) > RWY_HALF_LEN + 1e-3 or absf(z) > RWY_HALF_W + 1e-3
			row.append(Vector3(x, 0.0 if outside else 0.03, z))
		rows.append(row)
	kit.add_grid(rows, false, MeshKit.const_color(Color.WHITE), false, true)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/asphalt.gdshader")
	SurfaceTextures.initialize()
	mat.set_shader_parameter("aggregate_tex", SurfaceTextures.aggregate)
	mat.set_shader_parameter("aggregate_normal_tex", SurfaceTextures.aggregate_normal)
	mat.set_shader_parameter("half_len", RWY_HALF_LEN)
	mat.set_shader_parameter("half_wid", RWY_HALF_W)
	var mesh := ArrayMesh.new()
	kit.append_to(mesh, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.name = "Runway"
	add_child(mi)
	var hull := PackedVector3Array()
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			hull.append(Vector3(sx * RWY_HALF_LEN, 0.03, sz * RWY_HALF_W))
			hull.append(Vector3(sx * (RWY_HALF_LEN + bev), 0.0, sz * (RWY_HALF_W + bev)))
			hull.append(Vector3(sx * (RWY_HALF_LEN + bev), -0.17, sz * (RWY_HALF_W + bev)))
	_col_hull("runway", hull)
	# runway numbers
	label("09", Vector3(-RWY_HALF_LEN + 10.0, 0.065, 0), -PI * 0.5, 4.5, Color(0.85, 0.85, 0.82), true)
	label("27", Vector3(RWY_HALF_LEN - 10.0, 0.065, 0), PI * 0.5, 4.5, Color(0.85, 0.85, 0.82), true)
	# concrete pit pad and taxi path to the runway
	box(Vector3(-7.5, -0.18, 30.0), Vector3(79.0, 0.2, 22.0), Color(0.62, 0.61, 0.58), 3, "pad")
	# small concrete pilot pads
	for x in [-16.0, -8.0, 0.0, 8.0, 16.0]:
		box(Vector3(x, -0.17, 15.5), Vector3(2.6, 0.2, 2.2), Color(0.6, 0.59, 0.56), 3, "pad")
	# runway corner markers (cones)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var c := Vector3(sx * (RWY_HALF_LEN + 1.0), 0.0, sz * (RWY_HALF_W + 1.0))
			_kit(0).add_cylinder(c, c + Vector3(0, 0.45, 0), 0.16, 0.02, 10, MeshKit.const_color(_lin(Color(1.0, 0.35, 0.05))), true)
			_col_cyl("small", c, 0.14, 0.45)

# ================================================================ flight line
func _build_flightline() -> void:
	var z := 16.8
	var net_mat := ShaderMaterial.new()
	net_mat.shader = load("res://shaders/chainlink.gdshader")
	var net := MeshKit.new()
	var x := -60.0
	while x < 60.0:
		var x1 := minf(x + 3.0, 60.0)
		# leave walkway gaps at the pilot stations and the taxi path
		var gap := false
		for gx in [-16.0, -8.0, 0.0, 8.0, 16.0]:
			if absf((x + x1) * 0.5 - gx) < 1.0:
				gap = true
		if absf((x + x1) * 0.5 + 40.0) < 3.0:
			gap = true
		# posts
		cyl(Vector3(x, 0, z), Vector3(x, 1.35, z), 0.04, Color(0.3, 0.32, 0.3), 8, 6)
		_col_box("structure", Transform3D(Basis(), Vector3(x, 0.67, z)), Vector3(0.1, 1.35, 0.1))
		if not gap:
			net.add_quad(Vector3(x, 0.05, z), Vector3(x1, 0.05, z), Vector3(x1, 1.3, z), Vector3(x, 1.3, z), Color.WHITE, false, Vector3(0, 0, -1))
			cyl(Vector3(x, 1.3, z), Vector3(x1, 1.3, z), 0.025, Color(0.3, 0.32, 0.3), 8, 5)
			_col_box("net", Transform3D(Basis(), Vector3((x + x1) * 0.5, 0.67, z)), Vector3(x1 - x, 1.3, 0.06))
		x = x1
	cyl(Vector3(60, 0, z), Vector3(60, 1.35, z), 0.04, Color(0.3, 0.32, 0.3), 8, 6)
	var mesh := ArrayMesh.new()
	net.append_to(mesh, net_mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# pilot stations: transmitter stands + low wooden dividers
	for sx in [-16.0, -8.0, 0.0, 8.0, 16.0]:
		var sp := Vector3(sx + 1.1, 0.0, 16.0)
		cyl(sp, sp + Vector3(0, 1.0, 0), 0.03, Color(0.25, 0.25, 0.27), 8, 6)
		box(sp + Vector3(0, 1.0, 0), Vector3(0.45, 0.04, 0.3), Color(0.2, 0.2, 0.22), 5, "small")
		_col_box("small", Transform3D(Basis(), sp + Vector3(0, 0.5, 0)), Vector3(0.08, 1.0, 0.08))
		if absf(sx) > 0.1:
			box(Vector3(sx - 1.4, 0, 15.6), Vector3(0.08, 0.9, 1.2), Color(0.55, 0.42, 0.28), 1, "furniture")
	# spare transmitter on the centre stand
	box(Vector3(1.15, 1.04, 16.0), Vector3(0.2, 0.06, 0.14), Color(0.08, 0.08, 0.09), 5)
	cyl(Vector3(1.2, 1.1, 15.95), Vector3(1.2, 1.28, 15.95), 0.006, Color(0.1, 0.1, 0.1), 5, 4)

# ================================================================ pits
func _build_pits() -> void:
	for sx in [-30.0, -8.0]:
		_shelter(Vector3(sx, 0.02, 30.5), 18.0, 7.0)
	# charging station
	var cz := 25.0
	_table(Vector3(14.0, 0.02, cz), 0.0)
	box(Vector3(13.4, 0.79, cz), Vector3(0.35, 0.12, 0.25), Color(0.08, 0.08, 0.1), 5)
	box(Vector3(14.0, 0.79, cz), Vector3(0.35, 0.12, 0.25), Color(0.08, 0.08, 0.1), 5)
	box(Vector3(14.6, 0.79, cz), Vector3(0.25, 0.18, 0.2), Color(0.75, 0.1, 0.08), 0)
	label("CHARGING", Vector3(14.0, 1.35, cz - 0.6), PI, 0.28, Color(0.95, 0.95, 0.95))
	box(Vector3(14.0, 0.02, cz - 0.6), Vector3(0.06, 1.2, 0.06), Color(0.3, 0.3, 0.3), 8, "small")
	box(Vector3(14.0, 1.2, cz - 0.62), Vector3(1.4, 0.35, 0.03), Color(0.12, 0.35, 0.65), 0, "sign")
	# equipment cases / chairs / bins scattered with intent
	var case_cols := [Color(0.1, 0.1, 0.11), Color(0.25, 0.26, 0.28), Color(0.55, 0.1, 0.08), Color(0.12, 0.2, 0.4)]
	var spots := [Vector3(-35, 0.02, 24.5), Vector3(-22, 0.02, 24.0), Vector3(-13, 0.02, 24.6), Vector3(-2, 0.02, 24.2), Vector3(4, 0.02, 36.5), Vector3(-26, 0.02, 37.0)]
	for i in spots.size():
		var p: Vector3 = spots[i]
		box(p, Vector3(0.9, 0.42, 0.45), case_cols[i % 4], 5, "small", rng.randf_range(-0.4, 0.4))
		box(p + Vector3(0.9, 0, 0.2), Vector3(0.45, 0.32, 0.3), case_cols[(i + 1) % 4], 5, "small", rng.randf_range(-0.6, 0.6))
	for p in [Vector3(-38, 0.02, 26), Vector3(-20, 0.02, 26.5), Vector3(-5, 0.02, 26), Vector3(6, 0.02, 27), Vector3(10, 0.02, 34)]:
		_chair(p, rng.randf_range(-0.5, 0.5) + PI)
	for p in [Vector3(-42, 0.02, 22), Vector3(20, 0.02, 22), Vector3(26, 0.02, 38)]:
		_bin(p)
	for p in [Vector3(22, 0.02, 30), Vector3(22, 0.02, 34)]:
		_picnic(p, PI * 0.5)
	# aircraft stands on the ground near the flight line
	for p in [Vector3(-26, 0.02, 21.0), Vector3(-6, 0.02, 21.2)]:
		box(p + Vector3(0.0, 0, 0), Vector3(0.3, 0.35, 0.4), Color(0.1, 0.1, 0.1), 5, "small")
		box(p + Vector3(0.9, 0, 0), Vector3(0.3, 0.35, 0.4), Color(0.1, 0.1, 0.1), 5, "small")
	# hedge line behind the pits (soft foliage)
	for i in 10:
		_bush(Vector3(-46.0 + i * 8.0 + rng.randf_range(-1, 1), 0.0, 43.0 + rng.randf_range(-0.6, 0.6)), "hedge", i)

func _shelter(c: Vector3, w: float, d: float) -> void:
	var post_c := Color(0.45, 0.33, 0.22)
	var h := 2.7
	var nx := int(w / 4.5) + 1
	for i in nx:
		var x := c.x - w * 0.5 + i * (w / (nx - 1))
		for sz in [-1.0, 1.0]:
			box(Vector3(x, c.y, c.z + sz * d * 0.5), Vector3(0.16, h + (0.35 if sz > 0.0 else 0.0), 0.16), post_c, 1, "structure")
	# beams
	for sz in [-1.0, 1.0]:
		box(Vector3(c.x, c.y + h + (0.35 if sz > 0.0 else 0.0) - 0.2, c.z + sz * d * 0.5), Vector3(w + 0.3, 0.2, 0.18), post_c, 1, "structure")
	# roof (sloped corrugated)
	var slope := atan2(0.35, d)
	box(Vector3(c.x, c.y + h + 0.05, c.z - d * 0.5 - 0.4), Vector3(w + 1.0, 0.06, d + 1.2), Color(0.55, 0.56, 0.55), 2, "structure", 0.0, -slope)
	# tables with gear under the roof
	for i in 3:
		var tx := c.x - w * 0.33 + i * w * 0.33
		_table(Vector3(tx, c.y, c.z + 1.4), 0.0)
		_table(Vector3(tx, c.y, c.z - 1.6), 0.0)
		# field boxes, transmitters, batteries
		box(Vector3(tx - 0.6, c.y + 0.77, c.z + 1.4), Vector3(0.5, 0.25, 0.3), [Color(0.7, 0.1, 0.1), Color(0.1, 0.3, 0.6), Color(0.15, 0.15, 0.16)][i % 3], 5)
		box(Vector3(tx + 0.3, c.y + 0.77, c.z + 1.3), Vector3(0.22, 0.07, 0.15), Color(0.07, 0.07, 0.08), 5)
		box(Vector3(tx + 0.7, c.y + 0.77, c.z + 1.5), Vector3(0.14, 0.05, 0.05), Color(0.9, 0.75, 0.1), 5)
		box(Vector3(tx + 0.75, c.y + 0.77, c.z + 1.35), Vector3(0.14, 0.05, 0.05), Color(0.2, 0.5, 0.9), 5)
		# foam aircraft cradle
		box(Vector3(tx - 0.3, c.y + 0.77, c.z - 1.6), Vector3(0.12, 0.2, 0.3), Color(0.1, 0.1, 0.1), 6)
		box(Vector3(tx + 0.4, c.y + 0.77, c.z - 1.6), Vector3(0.12, 0.2, 0.3), Color(0.1, 0.1, 0.1), 6)
	# bench along the back
	_bench(Vector3(c.x - w * 0.25, c.y, c.z + d * 0.5 - 0.5), 0.0)
	_bench(Vector3(c.x + w * 0.25, c.y, c.z + d * 0.5 - 0.5), 0.0)

func _table(p: Vector3, yaw: float) -> void:
	var wood := Color(0.5, 0.38, 0.26)
	var b := Basis(Vector3.UP, yaw)
	box(p + b * Vector3(0, 0.72, 0), Vector3(2.4, 0.05, 0.9), wood, 1, "", yaw)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			box(p + b * Vector3(sx * 1.1, 0, sz * 0.38), Vector3(0.07, 0.72, 0.07), wood * 0.85, 1, "", yaw)
	_col_box("furniture", Transform3D(b, p + b * Vector3(0, 0.745, 0)), Vector3(2.4, 0.05, 0.9))
	_col_box("furniture", Transform3D(b, p + b * Vector3(-1.1, 0.36, 0)), Vector3(0.08, 0.72, 0.84))
	_col_box("furniture", Transform3D(b, p + b * Vector3(1.1, 0.36, 0)), Vector3(0.08, 0.72, 0.84))

func _bench(p: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	box(p + b * Vector3(0, 0.42, 0), Vector3(2.0, 0.05, 0.36), Color(0.55, 0.42, 0.28), 1, "", yaw)
	for sx in [-0.85, 0.85]:
		box(p + b * Vector3(sx, 0, 0), Vector3(0.08, 0.42, 0.34), Color(0.3, 0.3, 0.32), 8, "", yaw)
	_col_box("furniture", Transform3D(b, p + b * Vector3(0, 0.23, 0)), Vector3(2.0, 0.46, 0.38))

func _chair(p: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var cc = [Color(0.1, 0.2, 0.45), Color(0.15, 0.15, 0.16), Color(0.45, 0.1, 0.1)][rng.randi() % 3]
	box(p + b * Vector3(0, 0.42, 0), Vector3(0.5, 0.04, 0.45), cc, 6, "", yaw)
	box(p + b * Vector3(0, 0.44, 0.22), Vector3(0.5, 0.45, 0.04), cc, 6, "", yaw, -0.2)
	for sx in [-0.22, 0.22]:
		box(p + b * Vector3(sx, 0, 0), Vector3(0.03, 0.42, 0.45), Color(0.2, 0.2, 0.2), 8, "", yaw, 0.3)
	_col_box("furniture", Transform3D(b, p + b * Vector3(0, 0.45, 0.05)), Vector3(0.52, 0.9, 0.5))

func _bin(p: Vector3) -> void:
	_kit(0).add_cylinder(p, p + Vector3(0, 0.9, 0), 0.3, 0.32, 12, MeshKit.const_color(_lin(Color(0.12, 0.3, 0.16))), true)
	_col_cyl("small", p, 0.31, 0.9)

func _picnic(p: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	var wood := Color(0.52, 0.38, 0.24)
	box(p + b * Vector3(0, 0.74, 0), Vector3(1.9, 0.05, 0.8), wood, 1, "", yaw)
	for sz in [-0.62, 0.62]:
		box(p + b * Vector3(0, 0.44, sz), Vector3(1.9, 0.04, 0.28), wood, 1, "", yaw)
	for sx in [-0.7, 0.7]:
		box(p + b * Vector3(sx, 0, 0), Vector3(0.08, 0.74, 1.4), wood * 0.9, 1, "", yaw)
	_col_box("furniture", Transform3D(b, p + b * Vector3(0, 0.38, 0)), Vector3(1.9, 0.76, 1.55))

# ================================================================ buildings
func _build_clubhouse() -> void:
	var c := Vector3(47.0, 0.0, 34.0)
	var W := 13.0
	var D := 8.0
	var H := 3.0
	var wall := Color(0.86, 0.84, 0.78)
	box(c + Vector3(0, -0.1, 0), Vector3(W + 0.4, 0.3, D + 0.4), Color(0.55, 0.54, 0.5), 3)
	box(c + Vector3(0, 0.2, 0), Vector3(W, H, D), wall, 0, "structure")
	# gable roof
	var pitch := deg_to_rad(22.0)
	var half := D * 0.5 / cos(pitch) + 0.5
	box(c + Vector3(0, 0.2 + H, -D * 0.25 - 0.1), Vector3(W + 0.8, 0.12, half), Color(0.32, 0.18, 0.14), 2, "structure", 0.0, pitch)
	box(c + Vector3(0, 0.2 + H, D * 0.25 + 0.1), Vector3(W + 0.8, 0.12, half), Color(0.32, 0.18, 0.14), 2, "structure", 0.0, -pitch)
	for sx in [-1.0, 1.0]:
		var gk := _kit(0)
		var gx = c.x + sx * W * 0.5
		var col := _lin(wall * 0.95)
		gk.add_triangle(Vector3(gx, c.y + 0.2 + H, c.z - D * 0.5), Vector3(gx, c.y + 0.2 + H, c.z + D * 0.5), Vector3(gx, c.y + 0.2 + H + tan(pitch) * D * 0.5, c.z), col, false, Vector3(sx, 0, 0))
	# windows & door facing the pits (west, -x) and field (north, -z)
	for i in 3:
		box(Vector3(c.x - 4.0 + i * 3.5, 1.1, c.z - D * 0.5 - 0.03), Vector3(1.6, 1.1, 0.06), Color.BLACK, 7)
		box(Vector3(c.x - 4.0 + i * 3.5, 1.05, c.z - D * 0.5 - 0.05), Vector3(1.75, 0.08, 0.1), Color(0.95, 0.95, 0.95), 0)
	box(Vector3(c.x - W * 0.5 - 0.03, 0.2, c.z + 1.0), Vector3(0.06, 2.1, 1.0), Color(0.45, 0.28, 0.18), 1)
	box(Vector3(c.x - W * 0.5 - 0.03, 1.1, c.z - 2.2), Vector3(0.06, 1.1, 1.5), Color.BLACK, 7)
	# porch
	box(Vector3(c.x - W * 0.5 - 1.5, 0.0, c.z), Vector3(3.0, 0.25, 6.0), Color(0.5, 0.38, 0.26), 1, "structure")
	for sz in [-2.8, 2.8]:
		box(Vector3(c.x - W * 0.5 - 2.9, 0.25, c.z + sz), Vector3(0.14, 2.6, 0.14), Color(0.45, 0.33, 0.22), 1, "structure")
	box(Vector3(c.x - W * 0.5 - 1.5, 2.85, c.z), Vector3(3.3, 0.1, 6.3), Color(0.32, 0.18, 0.14), 2, "structure")
	label("RC PARK FLYERS", Vector3(c.x, 3.6, c.z - D * 0.5 - 0.35), PI, 0.55, Color(0.95, 0.95, 0.95))
	box(Vector3(c.x, 3.25, c.z - D * 0.5 - 0.3), Vector3(5.0, 0.75, 0.08), Color(0.12, 0.22, 0.38), 0)
	# storage / maintenance shed
	var s := Vector3(44.0, 0.0, 52.0)
	box(s, Vector3(7.0, 3.2, 5.5), Color(0.62, 0.64, 0.64), 2, "structure")
	box(s + Vector3(0, 3.2, 0), Vector3(7.4, 0.15, 6.0), Color(0.45, 0.47, 0.47), 2)
	box(Vector3(s.x - 3.52, 0.0, s.z), Vector3(0.05, 2.6, 3.0), Color(0.8, 0.8, 0.78), 2)
	# ride-on mower parked by the shed
	box(Vector3(s.x - 5.0, 0.12, s.z + 1.5), Vector3(1.1, 0.5, 1.6), Color(0.1, 0.45, 0.15), 4, "vehicle")
	box(Vector3(s.x - 5.0, 0.62, s.z + 1.8), Vector3(0.5, 0.45, 0.4), Color(0.1, 0.1, 0.1), 5)
	for sx in [-0.55, 0.55]:
		for sz in [-0.55, 0.6]:
			_kit(5).add_cylinder(Vector3(s.x - 5.0 + sx, 0.2, s.z + 1.5 + sz), Vector3(s.x - 5.0 + sx * 1.2, 0.2, s.z + 1.5 + sz), 0.2, 0.2, 10, MeshKit.const_color(Color(0.02, 0.02, 0.02)), true)

func _build_parking() -> void:
	var palette := [Color(0.75, 0.05, 0.05), Color(0.9, 0.9, 0.9), Color(0.1, 0.12, 0.15), Color(0.2, 0.3, 0.55), Color(0.55, 0.56, 0.58), Color(0.35, 0.4, 0.3), Color(0.85, 0.75, 0.55)]
	var x := -46.0
	var i := 0
	while x < 26.0:
		if rng.randf() < 0.8:
			var kind := rng.randi() % 3
			_car(Vector3(x, 0.0, 52.0 + rng.randf_range(-0.3, 0.3)), rng.randf_range(-0.06, 0.06) + PI * 0.5 * (1.0 if i % 2 == 0 else 1.0), palette[rng.randi() % palette.size()], kind)
		x += 3.2
		i += 1
	x = -40.0
	while x < 10.0:
		if rng.randf() < 0.6:
			_car(Vector3(x, 0.0, 63.0), -PI * 0.5 + rng.randf_range(-0.06, 0.06), palette[rng.randi() % palette.size()], rng.randi() % 3)
		x += 3.4
	_trailer(Vector3(16.0, 0.0, 62.0), -PI * 0.5)
	_trailer(Vector3(21.0, 0.0, 63.0), -PI * 0.5 + 0.1)

func _car(p: Vector3, yaw: float, colr: Color, kind: int) -> void:
	# kind 0 sedan, 1 SUV, 2 pickup. Local +x = front
	var b := Basis(Vector3.UP, yaw)
	var L := 4.6 if kind == 0 else (4.8 if kind == 1 else 5.4)
	var Wd := 1.8 if kind == 0 else 1.9
	var body_h := 0.75 if kind == 0 else 0.95
	var ride := 0.3 if kind == 0 else 0.4
	box(p + b * Vector3(0, ride, 0), Vector3(L, body_h, Wd), colr, 4, "", yaw)
	var cab_len := L * 0.5 if kind == 0 else (L * 0.6 if kind == 1 else L * 0.35)
	var cab_off := -L * 0.05 if kind == 0 else (-L * 0.12 if kind == 1 else L * 0.05)
	var cab_h := 0.6 if kind == 0 else 0.75
	box(p + b * Vector3(cab_off, ride + body_h, 0), Vector3(cab_len, cab_h, Wd * 0.94), colr, 4, "", yaw)
	# glass band
	box(p + b * Vector3(cab_off, ride + body_h + 0.08, 0), Vector3(cab_len + 0.02, cab_h * 0.62, Wd * 0.95), Color.BLACK, 7, "", yaw)
	if kind == 2:
		box(p + b * Vector3(-L * 0.3, ride + body_h - 0.1, 0), Vector3(L * 0.36, 0.12, Wd * 0.9), Color(0.05, 0.05, 0.05), 5, "", yaw)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var wc := p + b * Vector3(sx * L * 0.32, 0.36, sz * Wd * 0.46)
			_kit(5).add_cylinder(wc - b * Vector3(0, 0, 0.12 * sz), wc + b * Vector3(0, 0, 0.12 * sz), 0.36, 0.36, 12, MeshKit.const_color(Color(0.02, 0.02, 0.02)), true)
	# lights
	box(p + b * Vector3(L * 0.5, ride + body_h * 0.6, Wd * 0.33), Vector3(0.04, 0.12, 0.3), Color(0.95, 0.95, 0.9), 0, "", yaw)
	box(p + b * Vector3(L * 0.5, ride + body_h * 0.6, -Wd * 0.33), Vector3(0.04, 0.12, 0.3), Color(0.95, 0.95, 0.9), 0, "", yaw)
	box(p + b * Vector3(-L * 0.5, ride + body_h * 0.6, Wd * 0.35), Vector3(0.04, 0.12, 0.25), Color(0.8, 0.05, 0.05), 0, "", yaw)
	box(p + b * Vector3(-L * 0.5, ride + body_h * 0.6, -Wd * 0.35), Vector3(0.04, 0.12, 0.25), Color(0.8, 0.05, 0.05), 0, "", yaw)
	_col_box("vehicle", Transform3D(b, p + b * Vector3(0, ride * 0.5 + body_h * 0.5, 0)), Vector3(L, body_h + ride, Wd))
	_col_box("vehicle", Transform3D(b, p + b * Vector3(cab_off, ride + body_h + cab_h * 0.5, 0)), Vector3(cab_len, cab_h, Wd * 0.94))

func _trailer(p: Vector3, yaw: float) -> void:
	var b := Basis(Vector3.UP, yaw)
	box(p + b * Vector3(0, 0.45, 0), Vector3(4.2, 2.0, 2.1), Color(0.93, 0.93, 0.92), 0, "vehicle", yaw)
	box(p + b * Vector3(2.4, 0.4, 0), Vector3(0.9, 0.08, 0.12), Color(0.1, 0.1, 0.1), 8, "", yaw)
	label("RC PARK", p + b * Vector3(0, 1.6, 1.07), yaw, 0.4, Color(0.8, 0.1, 0.08))
	for sz in [-1.0, 1.0]:
		var wc := p + b * Vector3(0, 0.33, sz * 1.0)
		_kit(5).add_cylinder(wc - b * Vector3(0, 0, 0.12 * sz), wc + b * Vector3(0, 0, 0.12 * sz), 0.33, 0.33, 12, MeshKit.const_color(Color(0.02, 0.02, 0.02)), true)

func _build_perimeter() -> void:
	# split-rail fence around the club grounds (south side & sides of the parking)
	var pts := [Vector3(-90, 0, 78), Vector3(60, 0, 78), Vector3(60, 0, 20), Vector3(90, 0, 20)]
	for k in range(pts.size() - 1):
		var a: Vector3 = pts[k]
		var bpt: Vector3 = pts[k + 1]
		var L := a.distance_to(bpt)
		var n := int(L / 3.0)
		for i in n + 1:
			var p := a.lerp(bpt, float(i) / n)
			box(p, Vector3(0.14, 1.2, 0.14), Color(0.42, 0.32, 0.22), 1, "")
		var dirv := (bpt - a).normalized()
		var yaw := atan2(-dirv.z, dirv.x)
		for hy in [0.45, 0.95]:
			var c := (a + bpt) * 0.5
			box(c + Vector3(0, hy, 0), Vector3(L, 0.1, 0.08), Color(0.45, 0.35, 0.24), 1, "", yaw)
		_col_box("rail", Transform3D(Basis(Vector3.UP, yaw), (a + bpt) * 0.5 + Vector3(0, 0.6, 0)), Vector3(L, 1.2, 0.15))

func _build_windsock() -> void:
	var base := Vector3(-24.0, 0.0, -40.0)
	cyl(base, base + Vector3(0, 6.5, 0), 0.05, Color(0.8, 0.8, 0.82), 8, 8)
	_col_cyl("structure", base, 0.06, 6.5)
	windsock_pivot = Node3D.new()
	windsock_pivot.position = base + Vector3(0, 6.3, 0)
	add_child(windsock_pivot)
	var prev: Node3D = windsock_pivot
	var r0 := 0.22
	var seg_len := 0.36
	for i in 5:
		var seg := Node3D.new()
		seg.position = Vector3(0, 0, seg_len) if i > 0 else Vector3(0, 0, 0.05)
		prev.add_child(seg)
		var k := MeshKit.new()
		var ra := r0 * (1.0 - i * 0.12)
		var rb := r0 * (1.0 - (i + 1) * 0.12)
		var colr := Color(1.0, 0.35, 0.05) if i % 2 == 0 else Color(0.95, 0.95, 0.95)
		k.add_cylinder(Vector3.ZERO, Vector3(0, 0, seg_len), ra, rb, 12, MeshKit.const_color(_lin(colr)), false)
		var m := ArrayMesh.new()
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = 0.8
		k.append_to(m, mat)
		var mi := MeshInstance3D.new()
		mi.mesh = m
		seg.add_child(mi)
		windsock_segs.append(seg)
		prev = seg

func _build_signs() -> void:
	# entrance sign (like the club photos)
	var p := Vector3(-60.0, 0.0, 12.0)
	for sx in [-1.2, 1.2]:
		box(p + Vector3(sx, 0, 0), Vector3(0.14, 1.5, 0.14), Color(0.35, 0.26, 0.18), 1, "sign")
	box(p + Vector3(0, 1.0, 0), Vector3(3.0, 0.9, 0.08), Color(0.18, 0.18, 0.2), 0, "sign")
	label("RC PARK", p + Vector3(0, 1.6, -0.05), 0.0, 0.42, Color(0.95, 0.95, 0.95))
	label("FLYING FIELD", p + Vector3(0, 1.25, -0.05), 0.0, 0.28, Color(0.95, 0.6, 0.15))
	# safety signs on the flight line fence
	var s2 := Vector3(22.0, 0.0, 17.2)
	box(s2, Vector3(0.08, 1.2, 0.08), Color(0.3, 0.3, 0.3), 8, "sign")
	box(s2 + Vector3(0, 1.2, 0), Vector3(1.2, 0.7, 0.04), Color(0.95, 0.95, 0.95), 0, "sign")
	label("PILOTS ONLY", s2 + Vector3(0, 1.72, -0.03), 0.0, 0.16, Color(0.8, 0.1, 0.08))
	label("FLY SAFE\nRESPECT OTHERS", s2 + Vector3(0, 1.45, -0.03), 0.0, 0.1, Color(0.1, 0.1, 0.1))

# ================================================================ parked aircraft
func _build_parked_aircraft() -> void:
	var picks := [["tundra_cub", Vector3(-31.0, 0.8, 29.0), 0.4], ["viper90", Vector3(-9.0, 0.8, 32.0), -0.3],
		["skylark", Vector3(-20.0, 0.02, 22.0), 2.8], ["belle51", Vector3(2.0, 0.02, 22.6), 3.3]]
	for pk in picks:
		var id: String = pk[0]
		var a := Aircraft.new()
		a.setup(AircraftDB.by_id(id), {}, 1, true)
		add_child(a)
		var b := Basis(Vector3.UP, float(pk[2]))
		var low := 0.0
		for w in a.wheels:
			low = minf(low, (w["center"] as Vector3).y - float(w["r"]))
		var pos: Vector3 = pk[1]
		if pos.y > 0.5:
			pos.y = 0.77 + 0.18   # sitting in a cradle on the table
			low = 0.0
			a.gear_pos = 1.0
		a.global_transform = Transform3D(b, pos - Vector3(0, low, 0))
		a.collision_layer = Game.L_WORLD
		a.collision_mask = 0
		a.set_meta("kind", "parked_aircraft")
		a.set_meta("hardness", 0.9)
		a.update_visuals(a.global_transform, 0.0)
		_merge_static_visual(a)
		parked.append(a)

## Bake a static aircraft's many component meshes into one mesh per material (draw-call saver).
func _merge_static_visual(a: Aircraft) -> void:
	var root := a.visual_root
	var inv := root.global_transform.affine_inverse()
	var acc := {}
	var mis := []
	_collect_meshes(root, mis)
	for mi in mis:
		var m: MeshInstance3D = mi
		var rel := inv * m.global_transform
		var mesh := m.mesh as ArrayMesh
		if mesh == null:
			continue
		for si in mesh.get_surface_count():
			var mat := mesh.surface_get_material(si)
			if not acc.has(mat):
				acc[mat] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "u": PackedVector2Array(), "i": PackedInt32Array()}
			var A: Dictionary = acc[mat]
			var arr := mesh.surface_get_arrays(si)
			var base: int = (A["v"] as PackedVector3Array).size()
			for v in arr[Mesh.ARRAY_VERTEX]:
				(A["v"] as PackedVector3Array).append(rel * (v as Vector3))
			for n in arr[Mesh.ARRAY_NORMAL]:
				(A["n"] as PackedVector3Array).append((rel.basis * (n as Vector3)).normalized())
			var cols = arr[Mesh.ARRAY_COLOR]
			var uvs = arr[Mesh.ARRAY_TEX_UV]
			var cnt: int = (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			for k in cnt:
				(A["c"] as PackedColorArray).append(cols[k] if cols != null and k < cols.size() else Color.WHITE)
				(A["u"] as PackedVector2Array).append(uvs[k] if uvs != null and k < uvs.size() else Vector2.ZERO)
			for ix in arr[Mesh.ARRAY_INDEX]:
				(A["i"] as PackedInt32Array).append(base + int(ix))
		m.queue_free()
	var merged := ArrayMesh.new()
	for mat in acc.keys():
		var A: Dictionary = acc[mat]
		if (A["i"] as PackedInt32Array).is_empty():
			continue
		var arrs := []
		arrs.resize(Mesh.ARRAY_MAX)
		arrs[Mesh.ARRAY_VERTEX] = A["v"]
		arrs[Mesh.ARRAY_NORMAL] = A["n"]
		arrs[Mesh.ARRAY_COLOR] = A["c"]
		arrs[Mesh.ARRAY_TEX_UV] = A["u"]
		arrs[Mesh.ARRAY_INDEX] = A["i"]
		merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs)
		merged.surface_set_material(merged.get_surface_count() - 1, mat)
	var out := MeshInstance3D.new()
	out.mesh = merged
	root.add_child(out)
	a.set_process(false)

func _collect_meshes(n: Node, out: Array) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		_collect_meshes(c, out)

# ================================================================ trees & foliage
var _species_variants: Dictionary = {}

func _variant(species: String, idx: int, far: bool) -> Dictionary:
	var key := "%s_%d_%s" % [species, idx, far]
	if not _species_variants.has(key):
		_species_variants[key] = TreeLib.make(species, idx, far)
	return _species_variants[key]

func _build_trees_async(progress: Callable) -> void:
	var placements := []  # [species, variant, pos, yaw, scale, collide]
	# hero trees around the field edges (hazards you can actually hit)
	var heroes := [["oak", Vector3(88, 0, -46)], ["oak", Vector3(-110, 0, -55)], ["birch", Vector3(-84, 0, -38)],
		["oak", Vector3(128, 0, 12)], ["pine", Vector3(135, 0, -20)], ["birch", Vector3(118, 0, 30)], ["oak", Vector3(-128, 0, 18)],
		["poplar", Vector3(70, 0, 44)], ["poplar", Vector3(76, 0, 44)], ["oak", Vector3(-70, 0, 36)], ["birch", Vector3(30, 0, -62)],
		["pine", Vector3(-38, 0, -70)], ["oak", Vector3(0, 0, -95)]]
	for h in heroes:
		placements.append([h[0], rng.randi() % 3, h[1], rng.randf() * TAU, rng.randf_range(0.9, 1.15), true])
	# tree lines along the field boundary
	for i in 60:
		var x := -200.0 + i * 6.8 + rng.randf_range(-2.0, 2.0)
		var z := -112.0 + rng.randf_range(-6.0, 6.0)
		placements.append([["oak", "pine", "birch", "oak", "poplar"][rng.randi() % 5], rng.randi() % 3, Vector3(x, 0, z), rng.randf() * TAU, rng.randf_range(0.8, 1.2), true])
	for i in 40:
		var z2 := -100.0 + i * 5.2 + rng.randf_range(-2, 2)
		for sx in [-1.0, 1.0]:
			if rng.randf() < 0.75:
				placements.append([["oak", "pine", "birch"][rng.randi() % 3], rng.randi() % 3, Vector3(sx * (205.0 + rng.randf_range(-5, 8)), 0, z2), rng.randf() * TAU, rng.randf_range(0.8, 1.25), true])
	for i in 36:
		var x3 := -120.0 + i * 6.0 + rng.randf_range(-2, 2)
		placements.append([["oak", "poplar", "pine"][rng.randi() % 3], rng.randi() % 3, Vector3(x3, 0, 92.0 + rng.randf_range(-4, 6)), rng.randf() * TAU, rng.randf_range(0.85, 1.2), true])
	# bushes scattered near the field edges
	for i in 40:
		var a := rng.randf() * TAU
		var r := rng.randf_range(120.0, 190.0)
		var p := Vector3(cos(a) * r, 0, sin(a) * r * 0.55)
		if absf(p.z) < 20.0 and absf(p.x) < 90.0:
			continue
		placements.append(["bush", rng.randi() % 3, p, rng.randf() * TAU, rng.randf_range(0.8, 1.4), true])
	# forests on the hills (visual + trunk colliders)
	var forest_n := 2600  # World geometry/physics never changes with a graphics preset.
	var tries := 0
	var fcount := 0
	while fcount < forest_n and tries < forest_n * 6:
		tries += 1
		var x4 := rng.randf_range(-HALF * 0.97, HALF * 0.97)
		var z4 := rng.randf_range(-HALF * 0.97, HALF * 0.97)
		if absf(x4) < 250.0 and absf(z4) < 150.0:
			continue
		var fm := fnoise.get_noise_2d(x4, z4)
		if fm < 0.05 and rng.randf() > 0.08:
			continue
		placements.append([["pine", "oak", "pine", "birch"][rng.randi() % 4], rng.randi() % 3, Vector3(x4, 0, z4), rng.randf() * TAU, rng.randf_range(0.8, 1.3), false])
		fcount += 1
	progress.call(0.64, "Planting trees")
	await get_tree().process_frame
	# group by chunk for LOD MultiMeshes
	var chunk_size := 600.0
	var groups := {}
	for pl in placements:
		var p: Vector3 = pl[2]
		p.y = ground_y(p) - 0.05
		pl[2] = p
		var key := "%d_%d" % [int(floor(p.x / chunk_size)), int(floor(p.z / chunk_size))]
		var gkey := "%s|%s|%d" % [key, pl[0], int(pl[1]) % 2]
		if not groups.has(gkey):
			groups[gkey] = []
		(groups[gkey] as Array).append(pl)
	var gi := 0
	for gkey in groups.keys():
		var arr: Array = groups[gkey]
		var parts := String(gkey).split("|")
		var species := parts[1]
		var vi := int(parts[2])
		var near_v := _variant(species, vi, false)
		var far_v := _variant(species, vi, true)
		var center := Vector3.ZERO
		for pl in arr:
			center += pl[2]
		center /= arr.size()
		for lod in [0, 1]:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = (near_v if lod == 0 else far_v)["mesh"]
			mm.instance_count = arr.size()
			for k in arr.size():
				var pl: Array = arr[k]
				var xf := Transform3D(Basis(Vector3.UP, float(pl[3])).scaled(Vector3.ONE * float(pl[4])), (pl[2] as Vector3) - center)
				mm.set_instance_transform(k, xf)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.position = center
			if lod == 0:
				near_tree_nodes.append(mmi)
				mmi.visibility_range_end = 340.0
				mmi.visibility_range_end_margin = 40.0
				mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			else:
				mmi.visibility_range_begin = 300.0
				mmi.visibility_range_begin_margin = 40.0
				mmi.visibility_range_end = 1600.0
				mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				far_tree_nodes.append(mmi)
			add_child(mmi)
		# physics
		for pl in arr:
			_tree_physics(pl, near_v)
		gi += 1
		if gi % 12 == 0:
			progress.call(0.64 + 0.16 * float(gi) / groups.size(), "Planting trees")
			await get_tree().process_frame

var _forest_bodies: Dictionary = {}

func _tree_physics(pl: Array, v: Dictionary) -> void:
	var p: Vector3 = pl[2]
	var s := float(pl[4])
	var b := Basis(Vector3.UP, float(pl[3])).scaled(Vector3.ONE * s)
	var species := String(v["species"])
	if not bool(pl[5]):
		# Full canopy interaction without thousands of always-active Area3Ds.
		# These are the SAME conservative soft volumes used by nearby trees.
		for crown in v["canopy"]:
			outer_canopies.add(p + b * (crown[0] as Vector3), float(crown[1]) * s * 0.85,
				1.0 if species in ["bush", "hedge"] else (0.8 if species == "pine" else 0.6))
		# Solid trunks are still grouped per 300 m chunk into one static body.
		var key := "%d_%d" % [int(floor(p.x / 300.0)), int(floor(p.z / 300.0))]
		if not _forest_bodies.has(key):
			var fb := StaticBody3D.new()
			fb.collision_layer = Game.L_WORLD
			fb.set_meta("kind", "tree")
			fb.set_meta("hardness", 1.3)
			add_child(fb)
			_forest_bodies[key] = fb
		if species != "bush":
			var cs := CollisionShape3D.new()
			var cap := CylinderShape3D.new()
			cap.radius = float(v["trunk_r"]) * s
			cap.height = float(v["height"]) * s * 0.8
			cs.shape = cap
			cs.position = p + Vector3(0, cap.height * 0.5, 0)
			(_forest_bodies[key] as StaticBody3D).add_child(cs)
		return
	if species != "bush" and species != "hedge":
		var body := StaticBody3D.new()
		body.collision_layer = Game.L_WORLD
		body.set_meta("kind", "tree")
		body.set_meta("hardness", 1.3)
		body.position = p
		add_child(body)
		for l in v["limbs"]:
			var a: Vector3 = b * (l[0] as Vector3)
			var e: Vector3 = b * (l[1] as Vector3)
			var r := float(l[2]) * s
			if r < 0.06:
				continue   # thin branches are handled by the soft canopy volume
			var cs2 := CollisionShape3D.new()
			var cap2 := CapsuleShape3D.new()
			cap2.radius = r
			cap2.height = maxf(a.distance_to(e) + r * 2.0, r * 2.01)
			cs2.shape = cap2
			var mid := (a + e) * 0.5
			var up := (e - a).normalized()
			var bas := Basis(up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized(), up, Vector3.ZERO)
			bas.z = bas.x.cross(bas.y)
			cs2.transform = Transform3D(bas.orthonormalized(), mid)
			body.add_child(cs2)
	# soft foliage volumes
	for c in v["canopy"]:
		var ar := Area3D.new()
		ar.collision_layer = Game.L_FOLIAGE
		ar.collision_mask = 0
		ar.monitoring = false
		ar.monitorable = true
		var cs3 := CollisionShape3D.new()
		var sp := SphereShape3D.new()
		sp.radius = float(c[1]) * s * 0.85
		cs3.shape = sp
		ar.add_child(cs3)
		var cpos: Vector3 = p + b * (c[0] as Vector3)
		ar.position = cpos
		ar.set_meta("center", cpos)
		ar.set_meta("radius", sp.radius)
		ar.set_meta("density", 1.0 if species in ["bush", "hedge"] else (0.8 if species == "pine" else 0.6))
		add_child(ar)

func _bush(p: Vector3, species: String, idx: int) -> void:
	var v := _variant(species, idx % 3, false)
	p.y = ground_y(p)
	var mi := MeshInstance3D.new()
	mi.mesh = v["mesh"]
	mi.position = p
	mi.rotation.y = rng.randf() * TAU
	add_child(mi)
	_tree_physics([species, idx, p, mi.rotation.y, 1.0, true], v)

# ================================================================ grass
func _build_grass() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/grass_blades.gdshader")
	# clump mesh: 7 blades
	var kit := MeshKit.new()
	var r := RandomNumberGenerator.new()
	r.seed = 3
	for b in 7:
		var a := r.randf() * TAU
		var off := Vector3(r.randf_range(-0.07, 0.07), 0, r.randf_range(-0.07, 0.07))
		var h := r.randf_range(0.09, 0.23)
		var w := r.randf_range(0.003, 0.006)
		var d := Vector3(cos(a), 0, sin(a))
		var lean := Vector3(r.randf_range(-0.04, 0.04), 0, r.randf_range(-0.04, 0.04))
		var p0 := off - d * w
		var p1 := off + d * w
		var p2 := off + lean + Vector3(0, h, 0)
		var mid := off + lean * 0.3 + Vector3(0, h * 0.55, 0)
		var m0 := mid - d * w * 0.65
		var m1 := mid + d * w * 0.65
		var normal := Vector3(-d.z, 0.3, d.x).normalized()
		var color := Color(0.86 + r.randf() * 0.14, 1.0, 0.82 + r.randf() * 0.18)
		kit.add_triangle(p0, p1, m1, color, false, normal)
		kit.add_triangle(p0, m1, m0, color, false, normal)
		kit.add_triangle(m0, m1, p2, color, false, normal)
	var mesh := ArrayMesh.new()
	kit.append_to(mesh, mat)
	# placement regions: around the pilot line and runway edges (where the camera is close)
	var regions := [[Vector3(-60, 0, 7), Vector3(60, 0, 16.6), 1.3], [Vector3(-75, 0, -12), Vector3(75, 0, -6.2), 0.9], [Vector3(-75, 0, 6.2), Vector3(75, 0, 7), 1.2],
		[Vector3(-25, 0, -2), Vector3(25, 0, 30), 0.0]]
	# Preallocate the supported maximum once. Presets change visible instance count,
	# not placement order, allocations, collision geometry, or the world seed.
	var density := 3.2
	for reg in regions:
		var a: Vector3 = reg[0]
		var bb: Vector3 = reg[1]
		var dens := float(reg[2]) * density
		if dens <= 0.0:
			continue
		var area := (bb.x - a.x) * (bb.z - a.z)
		var count := int(area * dens * 1.6)
		# split into 40 m tiles so culling works
		var tiles_x := int(ceil((bb.x - a.x) / 40.0))
		for tx in tiles_x:
			var x0 := a.x + tx * 40.0
			var x1 := minf(x0 + 40.0, bb.x)
			var tcount := int(count * (x1 - x0) / (bb.x - a.x))
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mesh
			mm.instance_count = tcount
			var cen := Vector3((x0 + x1) * 0.5, 0, (a.z + bb.z) * 0.5)
			var placed := 0
			for k in tcount:
				var p := Vector3(r.randf_range(x0, x1), 0, r.randf_range(a.z, bb.z))
				if surface_at(p) == Game.SURF_ASPHALT:
					p.z += 0.9 * signf(p.z)
				p.y = ground_y(p)
				var s := r.randf_range(0.7, 1.4)
				mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(s, s * r.randf_range(0.8, 1.3), s)), p - cen))
				placed += 1
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.position = cen
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = 90.0
			add_child(mmi)
			grass_nodes.append(mmi)

# ================================================================ people
func _build_npcs() -> void:
	var pts := [Vector3(-34, 0, 27), Vector3(-26, 0, 34), Vector3(-12, 0, 27), Vector3(-4, 0, 33), Vector3(8, 0, 26),
		Vector3(14, 0, 29), Vector3(-18, 0, 22.5), Vector3(4, 0, 22.5), Vector3(30, 0, 33), Vector3(-40, 0, 24)]
	var starts := [Vector3(-30, 0, 29), Vector3(-10, 0, 26), Vector3(6, 0, 30), Vector3(-20, 0, 23), Vector3(12, 0, 24), Vector3(-6, 0, 16.0)]
	for i in starts.size():
		var n := NPC.new()
		add_child(n)
		n.setup(1000 + i, pts, starts[i])
		npcs.append(n)
	# one fellow pilot standing at the next station
	(npcs[5] as NPC).waypoints = [Vector3(-8, 0, 15.6), Vector3(-6, 0, 16.0)]

func reset_npcs() -> void:
	var i := 0
	for n in npcs:
		if is_instance_valid(n) and (n as NPC).down:
			(n as NPC).reset_to((n as NPC).target)
		i += 1

# ================================================================ gates (for courses)
func _build_gates() -> void:
	pass

func make_gates(points: Array) -> Array:
	for g in gates:
		if is_instance_valid(g):
			g.queue_free()
	gates.clear()
	var i := 0
	for p in points:
		var pos: Vector3 = p[0]
		var yaw: float = p[1]
		var radius := 3.2
		var g := Node3D.new()
		g.position = pos
		g.rotation.y = yaw
		add_child(g)
		var kit := MeshKit.new()
		var segs := 24
		var prevp := Vector3(radius, 0, 0)
		var col := MeshKit.const_color(Color(1.0, 0.45, 0.05).srgb_to_linear() if i > 0 else Color(0.1, 0.9, 0.3).srgb_to_linear())
		var body := StaticBody3D.new()
		body.collision_layer = Game.L_GATE
		body.set_meta("kind", "gate")
		body.set_meta("hardness", 0.8)
		g.add_child(body)
		for k in range(1, segs + 1):
			var a := TAU * float(k) / segs
			var np := Vector3(cos(a) * radius, sin(a) * radius, 0)
			kit.add_cylinder(prevp, np, 0.12, 0.12, 6, col, false)
			var cs := CollisionShape3D.new()
			var cap := CapsuleShape3D.new()
			cap.radius = 0.13
			cap.height = prevp.distance_to(np) + 0.26
			cs.shape = cap
			var mid := (prevp + np) * 0.5
			var up := (np - prevp).normalized()
			cs.transform = Transform3D(Basis(Vector3(0, 0, 1).cross(up), up, Vector3(0, 0, 1)).orthonormalized(), mid)
			body.add_child(cs)
			prevp = np
		var mesh := ArrayMesh.new()
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.5, 0.1) * 0.4
		kit.append_to(mesh, mat)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		g.add_child(mi)
		# trigger area inside the ring
		var ar := Area3D.new()
		ar.collision_layer = 0
		ar.collision_mask = Game.L_AIRCRAFT
		var cs2 := CollisionShape3D.new()
		var cyl2 := CylinderShape3D.new()
		cyl2.radius = radius - 0.2
		cyl2.height = 1.2
		cs2.shape = cyl2
		cs2.rotation.x = PI * 0.5
		ar.add_child(cs2)
		g.add_child(ar)
		g.set_meta("area", ar)
		g.set_meta("index", i)
		g.set_meta("mesh", mi)
		gates.append(g)
		i += 1
	return gates

# ================================================================ per-frame
func _process(delta: float) -> void:
	if Game.wind:
		var w: Vector3 = Game.wind.sample(Vector3(-24, 6.3, -40))
		var spd := w.length()
		if windsock_pivot:
			var target_yaw := atan2(w.x, w.z) if spd > 0.2 else windsock_pivot.rotation.y
			windsock_pivot.rotation.y = lerp_angle(windsock_pivot.rotation.y, target_yaw, clampf(delta * 1.5, 0, 1))
			# droop: calm = hangs down, ~7 m/s = fully horizontal
			var lift := clampf(spd / 7.0, 0.0, 1.0)
			var t := Time.get_ticks_msec() / 1000.0
			for i in windsock_segs.size():
				var seg: Node3D = windsock_segs[i]
				var droop := (1.0 - lift) * (0.42 + i * 0.05)
				var flap := sin(t * (6.0 + i * 1.3) + i) * 0.06 * (0.3 + lift)
				seg.rotation = Vector3(droop + flap, flap * 0.7, 0)
		cloud_off += Vector2(Game.wind.base_dir.x, Game.wind.base_dir.z) * (0.0006 + Game.wind.base_speed * 0.00012) * delta
		_cloud_t += delta
		if _cloud_t > 0.2:
			_cloud_t = 0.0
			sky_mat.set_shader_parameter("cloud_offset", cloud_off)
			if terrain_mat:
				terrain_mat.set_shader_parameter("cloud_shift", cloud_off * 420.0)

var _cloud_t := 0.0
