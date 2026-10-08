class_name Wind
extends RefCounted
## Single source of truth for wind. The aircraft, windsock, grass and trees all read
## this same field (visuals through shader globals updated from here).
## base vector + slow gust envelope + spatial turbulence + log-law shear near ground.

var base_speed := 3.0            # m/s at 10 m
var base_dir := Vector3(-1, 0, 0) # direction the wind blows TOWARD (world)
var gust_amp := 0.35             # fraction of base
var turb := 0.25                 # turbulence intensity (fraction)
var t := 0.0
var gust_now := 0.0
var _n1 := FastNoiseLite.new()
var _n2 := FastNoiseLite.new()
var _n3 := FastNoiseLite.new()
var enabled := true

const PRESETS := {
	"calm": {"speed": 0.0, "gust": 0.0, "turb": 0.0},
	"light": {"speed": 2.5, "gust": 0.3, "turb": 0.15},
	"moderate": {"speed": 5.0, "gust": 0.35, "turb": 0.22},
	"strong": {"speed": 8.0, "gust": 0.4, "turb": 0.3},
	"gusty": {"speed": 5.5, "gust": 0.75, "turb": 0.35},
}

func _init() -> void:
	_n1.seed = 11
	_n1.frequency = 0.05
	_n2.seed = 23
	_n2.frequency = 0.09
	_n3.seed = 37
	_n3.frequency = 0.07
	_n3.fractal_octaves = 2

func configure(preset: String, dir_mode: String, runway_heading: Vector3) -> void:
	var p: Dictionary = PRESETS.get(preset, PRESETS["light"])
	base_speed = float(p["speed"])
	gust_amp = float(p["gust"])
	turb = float(p["turb"])
	# runway_heading: direction aircraft take off toward. Headwind blows opposite to it.
	var h := runway_heading.normalized()
	var right := h.cross(Vector3.UP).normalized()
	match dir_mode:
		"headwind": base_dir = -h
		"tailwind": base_dir = h
		"crosswind_left": base_dir = right      # from the left, blowing to the right
		"crosswind_right": base_dir = -right
		"quartering": base_dir = (-h + right * 0.8).normalized()
		_: base_dir = (-h).rotated(Vector3.UP, 0.4)

func step(dt: float) -> void:
	t += dt
	gust_now = _n1.get_noise_1d(t * 10.0) * 0.6 + _n2.get_noise_1d(t * 10.0 + 100.0) * 0.4
	gust_now = clampf(gust_now * 1.6, -1.0, 1.0)

func speed_at_height(h: float) -> float:
	var z0 := 0.03
	var hh := maxf(h, 0.15)
	var f := log(hh / z0) / log(10.0 / z0)
	return base_speed * clampf(f, 0.2, 1.25)

func sample(p: Vector3) -> Vector3:
	if not enabled or base_speed <= 0.001:
		return Vector3.ZERO
	var h := maxf(p.y, 0.0)
	var s := speed_at_height(h) * (1.0 + gust_amp * gust_now)
	var w := base_dir * s
	if turb > 0.0:
		var q := p * 0.08 + base_dir * t * 0.8
		var tv := Vector3(_n3.get_noise_3d(q.x, q.y, q.z + t), _n3.get_noise_3d(q.x + 31.0, q.y, q.z - t * 0.7), _n3.get_noise_3d(q.x, q.y + 57.0, q.z + t * 0.5))
		var gnd := clampf(h / 3.0, 0.2, 1.0)  # vertical gusts damped near the ground
		tv.y *= gnd * 0.6
		w += tv * base_speed * turb * 2.2
	return w

var _pushed_dir := Vector2(1e9, 1e9)
var _pushed_strength := 1e9
var _pushed_gust := 1e9

## Every global shader parameter write touches the renderer's uniform buffer, so only changes that
## grass, trees and the windsock could actually show are pushed.
func push_shader_globals() -> void:
	var dir2 := Vector2(base_dir.x, base_dir.z)
	if dir2.distance_to(_pushed_dir) > 0.002:
		_pushed_dir = dir2
		RenderingServer.global_shader_parameter_set("wind_dir", dir2)
	var s := clampf(speed_at_height(2.0) * (1.0 + gust_amp * gust_now) / 8.0, 0.0, 1.5)
	if absf(s - _pushed_strength) > 0.004:
		_pushed_strength = s
		RenderingServer.global_shader_parameter_set("wind_strength", s)
	if absf(gust_now - _pushed_gust) > 0.01:
		_pushed_gust = gust_now
		RenderingServer.global_shader_parameter_set("wind_gust", gust_now)

func describe() -> String:
	if base_speed <= 0.01:
		return "Calm"
	return "%.0f km/h" % (base_speed * 3.6)
