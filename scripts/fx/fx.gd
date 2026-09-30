class_name Fx
extends Node3D
## Pre-allocated crash/impact effects. Nothing here allocates during a crash:
## particle emitters, fragment rigid bodies and sound players are pooled and
## re-armed round-robin, so crash #50 costs the same as crash #1.

const CHIPS := 40
var chips: Array = []
var chip_i := 0
var chip_time: Array = []
var dust_em: Array = []
var dust_i := 0
var grass_em: Array = []
var grass_i := 0
var chunk_em: Array = []
var chunk_i := 0
var leaf_em: Array = []
var leaf_i := 0

func setup() -> void:
	var chip_mesh := BoxMesh.new()
	chip_mesh.size = Vector3(0.05, 0.012, 0.035)
	chip_mesh.material = MatLib.chip()
	var chip_shape := BoxShape3D.new()
	chip_shape.size = chip_mesh.size
	for i in CHIPS:
		var rb := RigidBody3D.new()
		rb.collision_layer = Game.L_CHIP
		rb.collision_mask = Game.L_WORLD
		rb.mass = 0.01
		rb.freeze = true
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
		rb.linear_damp = 0.6
		rb.angular_damp = 1.0
		rb.can_sleep = true
		var cs := CollisionShape3D.new()
		cs.shape = chip_shape
		rb.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.mesh = chip_mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rb.add_child(mi)
		rb.visible = false
		rb.position = Vector3(0, -200, 0)
		add_child(rb)
		chips.append(rb)
		chip_time.append(0.0)
	var soft := _soft_texture()
	for i in 5:
		dust_em.append(_emitter(soft, Color(0.62, 0.55, 0.42, 0.55), 26, 1.6, 0.45, 2.4, false))
	for i in 4:
		grass_em.append(_emitter(soft, Color(0.35, 0.5, 0.18, 0.9), 30, 0.9, 0.06, 0.12, true))
	for i in 4:
		chunk_em.append(_emitter(null, Color(0.9, 0.9, 0.88, 1.0), 18, 1.4, 0.03, 0.05, true))
	for i in 3:
		leaf_em.append(_emitter(TreeLib.leaf_texture("small"), Color(0.45, 0.6, 0.25, 1.0), 16, 2.5, 0.12, 0.2, true))

func _soft_texture() -> ImageTexture:
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var d := Vector2(x - s * 0.5, y - s * 0.5).length() / (s * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _emitter(tex: Texture2D, col: Color, amount: int, life: float, size0: float, size1: float, gravity: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.92
	p.randomness = 0.5
	p.local_coords = false
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 3.2
	p.gravity = Vector3(0, -9.8 if gravity else 0.25, 0)
	p.damping_min = 0.8 if not gravity else 0.2
	p.damping_max = 2.0 if not gravity else 0.6
	p.angular_velocity_min = -180.0
	p.angular_velocity_max = 180.0
	p.scale_amount_min = size0
	p.scale_amount_max = size0 * 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.5))
	curve.add_point(Vector2(1.0, size1 / maxf(size0, 0.001) * 0.5 if not gravity else 0.5))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, col)
	grad.set_color(1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = grad
	var mesh: Mesh
	if tex:
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if not gravity else BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.albedo_texture = tex
		m.vertex_color_use_as_albedo = true
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		m.roughness = 1.0
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		q.material = m
		mesh = q
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3(1, 0.5, 0.7)
		var m2 := StandardMaterial3D.new()
		m2.vertex_color_use_as_albedo = true
		m2.roughness = 0.9
		bm.material = m2
		mesh = bm
	p.mesh = mesh
	p.position = Vector3(0, -300, 0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p

func _fire(pool: Array, idx: int, pos: Vector3, vel: Vector3, amount_scale: float, col := Color(-1, 0, 0)) -> int:
	var p: CPUParticles3D = pool[idx % pool.size()]
	p.visible = true
	p.global_position = pos
	p.initial_velocity_max = 1.5 + vel.length() * 0.35 * amount_scale + 1.5
	p.direction = (Vector3.UP + vel.normalized() * 0.6).normalized()
	if col.r >= 0.0:
		var g := p.color_ramp
		g.set_color(0, col)
		g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	p.restart()
	p.emitting = true
	return (idx + 1) % pool.size()

## pre-warm: fire everything once off-screen so pipelines/shaders are compiled
func prewarm(cam_pos: Vector3) -> void:
	for pool in [dust_em, grass_em, chunk_em, leaf_em]:
		for p in pool:
			(p as CPUParticles3D).global_position = cam_pos + Vector3(0, -2, -3)
			(p as CPUParticles3D).restart()
			(p as CPUParticles3D).emitting = true
	for i in 3:
		var rb: RigidBody3D = chips[i]
		rb.visible = true
		rb.global_position = cam_pos + Vector3(i * 0.1, -0.5, -2)

func end_prewarm() -> void:
	for pool in [dust_em, grass_em, chunk_em, leaf_em]:
		for p in pool:
			(p as CPUParticles3D).emitting = false
			(p as CPUParticles3D).restart()
			(p as CPUParticles3D).emitting = false
			(p as CPUParticles3D).global_position = Vector3(0, -300, 0)
			(p as CPUParticles3D).visible = false
	for i in 3:
		var rb: RigidBody3D = chips[i]
		rb.visible = false
		rb.global_position = Vector3(0, -200, 0)

func dust(pos: Vector3, vel: Vector3, amount := 1.0) -> void:
	var surf := Game.surface_at(pos)
	if surf in [Game.SURF_GRASS, Game.SURF_TALLGRASS]:
		grass_i = _fire(grass_em, grass_i, pos, vel, amount)
		if amount > 0.5:
			dust_i = _fire(dust_em, dust_i, pos, vel * 0.3, amount, Color(0.55, 0.52, 0.4, 0.35))
	else:
		dust_i = _fire(dust_em, dust_i, pos, vel * 0.5, amount, Color(0.62, 0.58, 0.5, 0.5))

func leaves(pos: Vector3, vel: Vector3) -> void:
	leaf_i = _fire(leaf_em, leaf_i, pos, vel, 1.0)
	Sfx.play3d("leaves", pos, 0.7, randf_range(0.8, 1.2))

func impact(pos: Vector3, normal: Vector3, material: String, strength: float, color: Color) -> void:
	dust(pos, normal * 3.0 * strength, strength)
	var snd := "impact_foam"
	match material:
		"film", "fabric": snd = "impact_wood"
		"composite": snd = "impact_composite"
		"metal", "painted": snd = "impact_composite" if strength < 0.6 else "impact_metal"
	Sfx.play3d(snd, pos, 0.4 + strength * 0.8, randf_range(0.85, 1.15))
	if strength > 0.35:
		_chips(pos, normal * 2.0, material, color, int(3 + strength * 5))

func breakup(pos: Vector3, vel: Vector3, material: String, color: Color, size: float) -> void:
	var col := color
	if material == "foam":
		chunk_i = _fire(chunk_em, chunk_i, pos, vel, 1.0, Color(0.92, 0.92, 0.9, 1.0))
	elif material in ["film", "fabric"]:
		chunk_i = _fire(chunk_em, chunk_i, pos, vel, 1.0, Color(0.75, 0.6, 0.38, 1.0))
	else:
		chunk_i = _fire(chunk_em, chunk_i, pos, vel, 1.0, Color(0.6, 0.6, 0.6, 1.0))
	_chips(pos, vel * 0.6, material, col, int(4 + size * 8))
	dust(pos, vel * 0.2, 1.0)
	var snd := "impact_wood" if material in ["film", "fabric"] else ("impact_foam" if material == "foam" else "impact_composite")
	Sfx.play3d(snd, pos, 1.3, randf_range(0.7, 0.95))
	Sfx.play3d("thud", pos, 1.0, randf_range(0.8, 1.1))

func debris_hit(pos: Vector3, sev: float, mass: float) -> void:
	if sev > 4.0:
		dust(pos, Vector3.UP * sev * 0.3, clampf(sev / 12.0, 0.2, 1.0))
	Sfx.play3d("thud", pos, clampf(sev / 10.0, 0.1, 1.0) * clampf(mass * 2.0, 0.3, 1.0), randf_range(0.9, 1.4))

func impact_sound(pos: Vector3, kind: String, vol: float) -> void:
	match kind:
		"gear": Sfx.play3d("gear", pos, vol, randf_range(0.9, 1.1))
		"person": Sfx.play3d("thud", pos, vol, 0.8)
		"branch": Sfx.play3d("branch", pos, vol, randf_range(0.9, 1.2))
		_: Sfx.play3d("thud", pos, vol)

func _chips(pos: Vector3, vel: Vector3, material: String, color: Color, n: int) -> void:
	var sub := MatLib.SUBSTRATE.get(material, Color(0.8, 0.8, 0.8)) as Color
	for k in mini(n, 10):
		var rb: RigidBody3D = chips[chip_i]
		chip_time[chip_i] = Time.get_ticks_msec()
		chip_i = (chip_i + 1) % CHIPS
		rb.visible = true
		rb.freeze = false
		rb.global_transform = Transform3D(Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, 0)), pos + Vector3(randf_range(-0.1, 0.1), randf_range(0.02, 0.15), randf_range(-0.1, 0.1)))
		rb.linear_velocity = vel + Vector3(randf_range(-2.5, 2.5), randf_range(1.0, 4.0), randf_range(-2.5, 2.5))
		rb.angular_velocity = Vector3(randf_range(-20, 20), randf_range(-20, 20), randf_range(-20, 20))
		var mi := rb.get_child(1) as MeshInstance3D
		var c := color if randf() < 0.6 else sub
		mi.set_instance_shader_parameter("tint", c)

func clear_chips() -> void:
	for rb in chips:
		(rb as RigidBody3D).freeze = true
		(rb as RigidBody3D).visible = false
		(rb as RigidBody3D).global_position = Vector3(0, -200, 0)

func active_chips() -> Array:
	var out := []
	for rb in chips:
		if (rb as RigidBody3D).visible:
			out.append(rb)
	return out
