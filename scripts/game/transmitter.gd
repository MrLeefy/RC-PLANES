class_name Transmitter
extends RefCounted
## Transmitter stick processing: dead zone -> expo curve -> rate (max travel) -> trim,
## then optional smoothing. "Linear / Direct" (expo 0, rate 1, dz 0) is exactly y = x.

var profile: Dictionary = {}
var _f := {"roll": 0.0, "pitch": 0.0, "yaw": 0.0}

func set_profile(p: Dictionary) -> void:
	profile = p.duplicate(true)

static func shape(x: float, ax: Dictionary) -> float:
	var s := signf(x)
	var a := absf(x)
	var dz := clampf(float(ax.get("dz", 0.0)), 0.0, 0.5)
	if a <= dz:
		a = 0.0
	elif dz > 0.0:
		a = (a - dz) / (1.0 - dz)
	var e := clampf(float(ax.get("expo", 0.0)), 0.0, 1.0)
	var y := (1.0 - e) * a + e * a * a * a
	return clampf(s * y * float(ax.get("rate", 1.0)) + float(ax.get("trim", 0.0)), -1.0, 1.0)

func process(roll: float, pitch: float, yaw: float, dt: float) -> Vector3:
	var out := Vector3(shape(roll, profile.get("roll", {})), shape(pitch, profile.get("pitch", {})), shape(yaw, profile.get("yaw", {})))
	var sm := float(profile.get("smoothing", 0.0))
	if sm <= 0.001:
		_f["roll"] = out.x; _f["pitch"] = out.y; _f["yaw"] = out.z
		return out
	var k := clampf(dt / sm, 0.0, 1.0)
	_f["roll"] = lerpf(float(_f["roll"]), out.x, k)
	_f["pitch"] = lerpf(float(_f["pitch"]), out.y, k)
	_f["yaw"] = lerpf(float(_f["yaw"]), out.z, k)
	return Vector3(_f["roll"], _f["pitch"], _f["yaw"])

func reset() -> void:
	_f = {"roll": 0.0, "pitch": 0.0, "yaw": 0.0}

func snapshot() -> Dictionary:
	return {"profile": profile.duplicate(true), "filter": _f.duplicate()}

func restore(state: Dictionary) -> void:
	profile = state["profile"].duplicate(true)
	_f = state["filter"].duplicate()