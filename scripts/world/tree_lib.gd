class_name TreeLib
extends RefCounted
## Procedural tree & bush species. Each species returns:
##  near mesh (bark + leaf cards, 2 surfaces), far mesh (few big cards),
##  collision description (trunk + major limbs), canopy volumes (soft foliage).

static var _leaf_textures: Dictionary = {}
static var _mats: Dictionary = {}

static func leaf_texture(kind: String) -> ImageTexture:
	if _leaf_textures.has(kind):
		return _leaf_textures[kind]
	var sz := 256
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var count := 110 if kind == "broad" else (320 if kind == "needle" else 240)
	for k in count:
		var cx := rng.randf_range(0.12, 0.88) * sz
		var cy := rng.randf_range(0.12, 0.88) * sz
		# denser toward the centre of the card
		var dcen := Vector2(cx - sz * 0.5, cy - sz * 0.5).length() / (sz * 0.5)
		if dcen > 0.97 or rng.randf() < dcen * 0.35:
			continue
		var ang := rng.randf() * TAU
		var L := rng.randf_range(10.0, 18.0) if kind == "broad" else (rng.randf_range(5.0, 9.0) if kind == "small" else rng.randf_range(10.0, 20.0))
		var W := L * (0.45 if kind != "needle" else 0.2)
		var shade := rng.randf_range(0.6, 1.0)
		var col := Color(shade * 0.85, shade, shade * 0.7, 1.0)
		var ca := cos(ang)
		var sa := sin(ang)
		var r := int(ceil(L))
		for yy in range(-r, r + 1):
			for xx in range(-r, r + 1):
				var u := xx * ca + yy * sa
				var v := -xx * sa + yy * ca
				var e := (u * u) / (L * L) + (v * v) / (W * W)
				if e <= 1.0:
					var px := int(cx) + xx
					var py := int(cy) + yy
					if px >= 0 and py >= 0 and px < sz and py < sz:
						var vein := 1.0 - 0.18 * exp(-v * v * 2.0)
						var edge := clampf((1.0 - e) * 3.0, 0.0, 1.0)
						img.set_pixel(px, py, Color(col.r * vein * (0.85 + 0.15 * edge), col.g * vein, col.b * vein, 1.0))
	# twigs
	for k in 6:
		var a0 := Vector2(sz * 0.5, sz * 0.5)
		var ang2 := rng.randf() * TAU
		for t in range(0, int(sz * 0.4)):
			var p := a0 + Vector2(cos(ang2), sin(ang2)) * t
			if p.x >= 0 and p.y >= 0 and p.x < sz and p.y < sz and img.get_pixelv(p).a < 0.5:
				img.set_pixelv(p, Color(0.25, 0.2, 0.14, 1.0))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_leaf_textures[kind] = tex
	return tex

static func leaf_material(kind: String, a: Color, b: Color, sway := 1.0) -> ShaderMaterial:
	var key := "%s_%s_%s" % [kind, a.to_html(), b.to_html()]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = MatLib.shader("res://shaders/leaves.gdshader")
	m.set_shader_parameter("leaf_tex", leaf_texture(kind))
	m.set_shader_parameter("tint_a", a)
	m.set_shader_parameter("tint_b", b)
	m.set_shader_parameter("sway", sway)
	_mats[key] = m
	return m

static func bark_material() -> ShaderMaterial:
	if _mats.has("bark"):
		return _mats["bark"]
	var m := ShaderMaterial.new()
	m.shader = MatLib.shader("res://shaders/bark.gdshader")
	_mats["bark"] = m
	return m

## Species definition -> Dictionary with meshes & physics description
static func make(species: String, seed_i: int, far := false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_i * 7919 + hash(species)
	var bark := MeshKit.new()
	var leaves := MeshKit.new()
	var limbs := []      # [a, b, radius]
	var canopy := []     # [center, radius]
	var height := 12.0
	var trunk_r := 0.3
	var bark_col := Color(0.34, 0.27, 0.2)
	var leaf_kind := "broad"
	var ta := Color(0.30, 0.44, 0.16)
	var tb := Color(0.20, 0.34, 0.10)
	match species:
		"oak":
			height = rng.randf_range(10.0, 15.0)
			trunk_r = height * 0.03
			var crown_h := height * 0.42
			limbs.append([Vector3.ZERO, Vector3(0, crown_h, 0), trunk_r])
			var nl := 5
			for i in nl:
				var a := TAU * i / nl + rng.randf_range(-0.3, 0.3)
				var dirv := Vector3(cos(a), rng.randf_range(0.7, 1.2), sin(a)).normalized()
				var L := height * rng.randf_range(0.35, 0.5)
				var s := Vector3(0, crown_h * rng.randf_range(0.8, 1.0), 0)
				limbs.append([s, s + dirv * L, trunk_r * 0.45])
				canopy.append([s + dirv * L * 1.05, height * rng.randf_range(0.2, 0.26)])
			canopy.append([Vector3(0, height * 0.78, 0), height * 0.3])
		"pine":
			height = rng.randf_range(14.0, 22.0)
			trunk_r = height * 0.018
			limbs.append([Vector3.ZERO, Vector3(0, height, 0), trunk_r])
			leaf_kind = "needle"
			ta = Color(0.16, 0.28, 0.12)
			tb = Color(0.10, 0.22, 0.10)
			bark_col = Color(0.36, 0.25, 0.18)
			for i in 6:
				var t := 0.3 + i * 0.12
				canopy.append([Vector3(0, height * t, 0), height * (0.26 - i * 0.03)])
		"birch":
			height = rng.randf_range(9.0, 13.0)
			trunk_r = height * 0.018
			bark_col = Color(0.72, 0.71, 0.68)
			leaf_kind = "small"
			ta = Color(0.45, 0.58, 0.22)
			tb = Color(0.34, 0.5, 0.18)
			limbs.append([Vector3.ZERO, Vector3(0, height * 0.9, 0), trunk_r])
			for i in 3:
				var a := TAU * i / 3.0 + rng.randf()
				var s := Vector3(0, height * rng.randf_range(0.45, 0.65), 0)
				var dv := Vector3(cos(a) * 0.5, 1.0, sin(a) * 0.5).normalized()
				limbs.append([s, s + dv * height * 0.3, trunk_r * 0.4])
				canopy.append([s + dv * height * 0.3, height * 0.17])
			canopy.append([Vector3(0, height * 0.75, 0), height * 0.22])
		"poplar":
			height = rng.randf_range(15.0, 20.0)
			trunk_r = height * 0.02
			limbs.append([Vector3.ZERO, Vector3(0, height * 0.85, 0), trunk_r])
			ta = Color(0.28, 0.42, 0.15)
			tb = Color(0.2, 0.34, 0.1)
			for i in 5:
				canopy.append([Vector3(0, height * (0.35 + i * 0.13), 0), height * (0.13 + 0.02 * sin(i))])
		"bush":
			height = rng.randf_range(1.4, 2.4)
			trunk_r = 0.05
			leaf_kind = "small"
			ta = Color(0.26, 0.40, 0.14)
			tb = Color(0.18, 0.30, 0.10)
			for i in 4:
				var off := Vector3(rng.randf_range(-0.6, 0.6), height * rng.randf_range(0.35, 0.6), rng.randf_range(-0.6, 0.6))
				canopy.append([off, height * rng.randf_range(0.35, 0.5)])
		"hedge":
			height = 1.8
			leaf_kind = "small"
			ta = Color(0.2, 0.33, 0.1)
			tb = Color(0.16, 0.28, 0.09)
			for i in 5:
				canopy.append([Vector3(-2.0 + i * 1.0, 0.9, 0), 0.9])
	# ---- bark geometry
	var bc := MeshKit.const_color(bark_col.srgb_to_linear())
	if not far:
		for l in limbs:
			bark.add_cylinder(l[0], l[1], float(l[2]), float(l[2]) * 0.55, 7, bc, false)
		if trunk_r > 0.08:
			# root flare
			bark.add_cylinder(Vector3(0, -0.2, 0), Vector3(0, 0.6, 0), trunk_r * 1.6, trunk_r, 7, bc, false)
	else:
		if limbs.size() > 0:
			var l0: Array = limbs[0]
			bark.add_cylinder(l0[0], l0[1], float(l0[2]), float(l0[2]) * 0.6, 4, bc, false)
	# ---- leaf cards: quads scattered in canopy volumes with outward normals
	var per_vol := 0
	for c in canopy:
		var cen: Vector3 = c[0]
		var rad: float = c[1]
		var n: int
		if far:
			n = 3 if species != "pine" else 2
		else:
			n = int(clampf(rad * rad * 3.0, 10.0, 56.0))
			if species == "pine":
				n = int(clampf(rad * rad * 3.5, 14.0, 44.0))
		per_vol += n
		for k in n:
			var dirv := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.7, 1), rng.randf_range(-1, 1)).normalized()
			var pos := cen + dirv * rad * rng.randf_range(0.35, 0.95)
			if species == "pine":
				pos = cen + Vector3(dirv.x, dirv.y * 0.25, dirv.z).normalized() * rad * rng.randf_range(0.2, 1.0) * Vector3(1, 0.3, 1)
			var cs := rad * (1.15 if not far else 1.9) * rng.randf_range(0.75, 1.1)
			if species == "hedge":
				cs = 1.1
			var up := Vector3(rng.randf_range(-0.3, 0.3), 1, rng.randf_range(-0.3, 0.3)).normalized()
			var right := dirv.cross(up).normalized()
			if right.length_squared() < 0.1:
				right = Vector3.RIGHT
			var upv := right.cross(dirv).normalized()
			if far:
				right = Vector3(cos(k * 1.1), 0, sin(k * 1.1))
				upv = Vector3.UP
			var nrm := (pos - cen).normalized().lerp(Vector3.UP, 0.25).normalized()
			var shade := clampf(0.55 + 0.45 * ((pos.y - cen.y) / maxf(rad, 0.1) * 0.5 + 0.5), 0.3, 1.0)
			var col := Color(shade, shade, shade, 1.0)
			var h := cs * 0.5
			var p0 := pos - right * h - upv * h
			var p1 := pos + right * h - upv * h
			var p2 := pos + right * h + upv * h
			var p3 := pos - right * h + upv * h
			var i0 := leaves.verts.size()
			for q in [[p0, Vector2(0, 1)], [p1, Vector2(1, 1)], [p2, Vector2(1, 0)], [p3, Vector2(0, 0)]]:
				leaves.verts.append(q[0])
				leaves.norms.append(nrm)
				leaves.cols.append(col)
				leaves.uvs.append(q[1])
			for lst in [leaves.idx, leaves.lod1, leaves.lod2]:
				lst.append_array(PackedInt32Array([i0, i0 + 2, i0 + 1, i0, i0 + 3, i0 + 2]))
	var mesh := ArrayMesh.new()
	bark.append_to(mesh, bark_material())
	leaves.append_to(mesh, leaf_material(leaf_kind, ta, tb, 1.0 if species != "hedge" else 0.4))
	return {"mesh": mesh, "height": height, "trunk_r": trunk_r, "limbs": limbs, "canopy": canopy, "species": species}