class_name CameraRig
extends Camera3D
## Flight & replay cameras. Cameras never constrain the aircraft; they only
## follow it. Damped, velocity-aware, and pushed out of scenery by raycasts.

const MODES := ["pilot", "chase", "locked", "onboard", "free"]
const REPLAY_MODES := ["cinematic", "chase", "wreck", "orbit", "pilot", "part"]

var mode := "pilot"
var target: Aircraft = null
var target_xf := Transform3D()
var target_vel := Vector3.ZERO
var pilot_pos := Vector3(0, 1.7, 15.2)
var auto_zoom := true
var orbit_yaw := 0.6
var orbit_pitch := 0.25
var orbit_dist := 6.0
var _pos := Vector3.ZERO
var _look := Vector3.ZERO
var _vel := Vector3.ZERO
var _fov := 50.0
var _up := Vector3.UP
var cine_pos := Vector3.ZERO
var cine_valid := false
var part_index := -1
var replay_focus := Vector3.ZERO
var replay_aircraft_focus := Vector3.ZERO
var override_target := false
var hangar_offset := 0.0   # frames the display aircraft left of the hangar info panel
var _rq := PhysicsRayQueryParameters3D.new()
var _sweep := PhysicsShapeQueryParameters3D.new()
var _camera_shape := SphereShape3D.new()
var shot_clock := 0.0
var shot_origin := Vector3.ZERO
var shot_velocity := Vector3.ZERO
var _shot_index := -9999
var _live_clock := 0.0
var cine_picks := 0
const SHOT_SECONDS := 3.5

func _ready() -> void:
	near = 0.05
	far = 5000.0
	fov = 50.0
	doppler_tracking = Camera3D.DOPPLER_TRACKING_IDLE_STEP
	current = true
	_rq.collision_mask = Game.L_WORLD
	_camera_shape.radius = 0.18
	_sweep.shape = _camera_shape
	_sweep.collision_mask = Game.L_WORLD
	_sweep.margin = 0.04
	process_mode = Node.PROCESS_MODE_ALWAYS

func set_mode(m: String) -> void:
	mode = m
	cine_valid = false
	_shot_index = -9999
	if m == "free" or m == "orbit":
		orbit_dist = clampf(target.span * 3.5 if target else 5.0, 2.5, 14.0)

func next_mode(list: Array) -> String:
	var i := list.find(mode)
	set_mode(list[(i + 1) % list.size()])
	return mode

func snap() -> void:
	_pos = _desired_pos()
	_look = _desired_look()
	global_position = _pos
	_orient(_look, _up)

func _aircraft_xf() -> Transform3D:
	if override_target:
		return target_xf
	if target and is_instance_valid(target):
		return target.vis_xf if target.vis_xf != Transform3D() else target.global_transform
	return Transform3D(Basis(), Vector3(0, 1, 0))

func _aircraft_vel() -> Vector3:
	if override_target:
		return target_vel
	if target and is_instance_valid(target):
		return target.linear_velocity
	return Vector3.ZERO

func _focus_point() -> Vector3:
	if override_target:
		return replay_aircraft_focus
	var xf := _aircraft_xf()
	var com := target.com_local if target else Vector3.ZERO
	return xf * com

func _desired_pos() -> Vector3:
	var xf := _aircraft_xf()
	var f := _focus_point()
	var v := _aircraft_vel()
	var span := target.span if target else 1.5
	var L := target.length_m if target else 1.2
	match mode:
		"pilot":
			return pilot_pos
		"chase":
			var hdg := v * Vector3(1, 0, 1)
			if hdg.length() < 2.0:
				hdg = -xf.basis.z * Vector3(1, 0, 1)
			hdg = hdg.normalized() if hdg.length() > 0.01 else Vector3.FORWARD
			var d := clampf(span * 2.6 + L * 1.5, 3.0, 14.0)
			return f - hdg * d + Vector3(0, d * 0.28, 0)
		"locked":
			var d2 := clampf(span * 2.2 + L * 1.3, 2.5, 12.0)
			return xf * (target.com_local if target else Vector3.ZERO) + xf.basis * Vector3(0, d2 * 0.25, d2)
		"onboard":
			var cz := float((target.def["canopy"] as Dictionary).get("z1", L * 0.4)) if target else 0.4
			return xf * Vector3(0, (target.def["canopy"].get("y", 0.1) if target else 0.1) + 0.08 * L, cz + L * 0.08)
		"free", "orbit":
			var dir := Vector3(cos(orbit_pitch) * sin(orbit_yaw), sin(orbit_pitch), cos(orbit_pitch) * cos(orbit_yaw))
			return f + dir * orbit_dist
		"cinematic":
			var clock := shot_clock if override_target else _live_clock
			var shot := int(floor(clock / SHOT_SECONDS))
			if not cine_valid or shot != _shot_index:
				_shot_index = shot
				_pick_cine(shot_origin if override_target else f, shot_velocity if override_target else v)
			return cine_pos
		"part":
			var direction := Vector3(cos(orbit_pitch) * sin(orbit_yaw), sin(orbit_pitch), cos(orbit_pitch) * cos(orbit_yaw))
			return replay_focus + direction * orbit_dist
		"wreck":
			var d3 := clampf(span * 2.4, 3.0, 10.0)
			var side := Vector3(sin((shot_clock if override_target else _live_clock) * 0.12), 0, cos((shot_clock if override_target else _live_clock) * 0.12))
			return replay_focus + side * d3 + Vector3(0, d3 * 0.45, 0)
	return pilot_pos

func _pick_cine(focus: Vector3, velocity: Vector3) -> void:
	var heading := velocity * Vector3(1, 0, 1)
	if heading.length() < 1.0: heading = Vector3.RIGHT
	heading = heading.normalized()
	var side := heading.cross(Vector3.UP) * (1.0 if _shot_index % 2 == 0 else -1.0)
	var span := target.span if target else 1.5
	var distance := clampf(span * 6.0, 8.0, 20.0)
	var p := focus + heading * distance + side * distance * 0.7
	var ground: float = Game.field.ground_y(p) if Game.field else 0.0
	# Relative altitude is essential: a high aircraft must not repeatedly select
	# a camera on the grass tens/hundreds of metres below it.
	p.y = maxf(focus.y + maxf(0.8, span * 0.6), ground + 1.2)
	cine_pos = _avoid(focus, p)
	cine_valid = true
	cine_picks += 1

func _desired_look() -> Vector3:
	var f := _focus_point()
	var v := _aircraft_vel()
	match mode:
		"pilot":
			return f + v * 0.06
		"chase":
			return f + v * 0.25 + Vector3(0, 0.3, 0)
		"locked":
			return f + _aircraft_xf().basis * Vector3(0, 0, -3.0)
		"onboard":
			return _aircraft_xf() * Vector3(0, 0, -30.0)
		"wreck", "part":
			return replay_focus
	return f

func _process(delta: float) -> void:
	if not get_tree().paused:
		_live_clock += delta
	if target == null and not override_target:
		return
	var dp := _desired_pos()
	var dl := _desired_look()
	var up := Vector3.UP
	match mode:
		"pilot":
			_pos = dp
			_look = _look.lerp(dl, clampf(delta * 14.0, 0.0, 1.0)) if _look != Vector3.ZERO else dl
		"chase":
			_pos = _pos.lerp(dp, clampf(delta * 3.5, 0.0, 1.0))
			_look = _look.lerp(dl, clampf(delta * 8.0, 0.0, 1.0))
		"locked":
			_pos = _pos.lerp(dp, clampf(delta * 8.0, 0.0, 1.0))
			_look = _look.lerp(dl, clampf(delta * 10.0, 0.0, 1.0))
			up = _up.slerp(_aircraft_xf().basis.y, clampf(delta * 6.0, 0.0, 1.0)) if _up.length() > 0.5 else _aircraft_xf().basis.y
		"onboard":
			_pos = dp
			_look = dl
			up = _aircraft_xf().basis.y
		"free", "orbit":
			_pos = _pos.lerp(dp, clampf(delta * 10.0, 0.0, 1.0))
			_look = dl
			if hangar_offset > 0.0:
				var right := (dl - _pos).cross(Vector3.UP).normalized()
				_look = dl + right * hangar_offset + Vector3(0, hangar_offset * 0.15, 0)
		"cinematic":
			_pos = dp
			_look = _look.lerp(dl, clampf(delta * 9.0, 0.0, 1.0))
		_:
			_pos = _pos.lerp(dp, clampf(delta * 4.0, 0.0, 1.0))
			_look = _look.lerp(dl, clampf(delta * 6.0, 0.0, 1.0))
	_up = up
	var final := _avoid(dl, _pos) if mode in ["cinematic", "chase", "locked", "free", "orbit", "wreck", "part"] else _pos
	global_position = final
	_orient(_look, up)
	# FOV: auto zoom in pilot/cinematic views keeps the model a readable size
	var target_fov := 60.0
	if mode in ["pilot", "cinematic"] and auto_zoom and target:
		var dist := final.distance_to(_focus_point())
		var sz := maxf(target.span, target.length_m) * 3.0
		target_fov = clampf(rad_to_deg(2.0 * atan(sz / maxf(dist, 0.1))), 5.0, 62.0)
	elif mode == "onboard":
		target_fov = 72.0
	elif hangar_offset > 0.0:
		target_fov = 42.0
	_fov = lerpf(_fov, target_fov, clampf(delta * 3.0, 0.0, 1.0))
	fov = _fov
	RenderingServer.global_shader_parameter_set("cam_pos", final)
	if Game.field:
		Game.field.focus_shadows(final.distance_to(_focus_point()))

func _orient(look: Vector3, up: Vector3) -> void:
	var dirv := look - global_position
	if dirv.length() < 0.001:
		return
	var u := up
	if absf(dirv.normalized().dot(u)) > 0.995:
		u = Vector3.FORWARD if absf(dirv.normalized().dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	look_at(look, u)

func _avoid(from: Vector3, to: Vector3) -> Vector3:
	var world := get_world_3d()
	if world == null: return to
	var space := world.direct_space_state
	var p := to
	if Game.field: p.y = maxf(p.y, Game.field.ground_y(p) + 0.3)
	_rq.from = from
	_rq.to = p
	_rq.exclude = [target.get_rid()] if is_instance_valid(target) else []
	var hit := space.intersect_ray(_rq)
	if not hit.is_empty():
		p = (hit["position"] as Vector3) + (hit["normal"] as Vector3) * 0.28
	# A volume sweep protects the near plane, not just the optical centre.
	_sweep.transform = Transform3D(Basis(), from)
	_sweep.motion = p - from
	_sweep.exclude = _rq.exclude
	var fractions := space.cast_motion(_sweep)
	if fractions.size() >= 2 and fractions[0] < 1.0:
		p = from + (p - from) * maxf(0.0, fractions[0] - 0.015)
	if Game.field: p.y = maxf(p.y, Game.field.ground_y(p) + 0.3)
	# Starting inside a collider is not reported by cast_motion. Check the
	# endpoint and use deterministic escape candidates for an embedded wreck.
	_sweep.motion = Vector3.ZERO
	_sweep.transform.origin = p
	if not space.intersect_shape(_sweep, 1).is_empty():
		for offset in [Vector3.UP * 2.0, Vector3(2,2,0), Vector3(-2,2,0), Vector3(0,3,3), Vector3(0,3,-3), Vector3.UP * 6.0]:
			var candidate: Vector3 = from + offset
			if Game.field: candidate.y = maxf(candidate.y, Game.field.ground_y(candidate) + 0.5)
			_sweep.transform.origin = candidate
			if space.intersect_shape(_sweep, 1).is_empty():
				p = candidate
				break
	return p

func orbit_drag(rel: Vector2) -> void:
	orbit_yaw -= rel.x * 0.006
	orbit_pitch = clampf(orbit_pitch + rel.y * 0.004, -0.2, 1.35)

func orbit_zoom(f: float) -> void:
	orbit_dist = clampf(orbit_dist * f, 1.2, 40.0)