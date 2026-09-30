extends Node
## Local diagnostics: frame times, recent inputs, physics state and collisions.
## Nothing leaves the device; export writes a JSON file under user://.

const FRAMES := 900
var frame_ms := PackedFloat32Array()
var frame_i := 0
var inputs: Array = []
var collisions: Array = []
var events: Array = []
var worst_ms := 0.0
var crash_frame_ms: Array = []
var _last_us := 0
var overlay_enabled := false
var physics_state: Dictionary = {}

func _ready() -> void:
	frame_ms.resize(FRAMES)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_last_us = Time.get_ticks_usec()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := (now - _last_us) / 1000.0
	_last_us = now
	frame_ms[frame_i % FRAMES] = ms
	frame_i += 1
	if frame_i > 30:
		worst_ms = maxf(worst_ms * 0.9995, ms)

func stats() -> Dictionary:
	var n := mini(frame_i, FRAMES)
	if n < 2:
		return {"avg_fps": 0.0, "avg_ms": 0.0, "p99_ms": 0.0, "worst_ms": 0.0}
	var arr := []
	var sum := 0.0
	for i in n:
		arr.append(frame_ms[i])
		sum += frame_ms[i]
	arr.sort()
	var p99: float = arr[int(n * 0.99) - 1] if n > 100 else arr[n - 1]
	var avg := sum / n
	return {"avg_fps": 1000.0 / maxf(avg, 0.001), "avg_ms": avg, "p99_ms": p99, "low1_fps": 1000.0 / maxf(p99, 0.001), "worst_ms": arr[n - 1]}

func log_input(v: Array) -> void:
	inputs.append([Time.get_ticks_msec(), v])
	if inputs.size() > 300:
		inputs.pop_front()

func log_collision(aircraft: String, comp: String, sev: float, kind: String) -> void:
	collisions.append({"t": Time.get_ticks_msec(), "aircraft": aircraft, "comp": comp, "sev": snappedf(sev, 0.01), "kind": kind})
	if collisions.size() > 80:
		collisions.pop_front()

func log_event(txt: String) -> void:
	events.append([Time.get_ticks_msec(), txt])
	if events.size() > 100:
		events.pop_front()

func mark_crash_frame(ms: float) -> void:
	crash_frame_ms.append(ms)
	if crash_frame_ms.size() > 60:
		crash_frame_ms.pop_front()

func export_report(extra: Dictionary = {}) -> Dictionary:
	var rep := {
		"game_version": Game.VERSION,
		"measurement_environment": "headless CPU (not phone FPS)" if DisplayServer.get_name() == "headless" else "rendered runtime; identify device before comparing",
		"render_scale": get_viewport().scaling_3d_scale,
		"physics_frame_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"engine": Engine.get_version_info().get("string", ""),
		"os": OS.get_name(),
		"model": OS.get_model_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"frame_stats": stats(),
		"recent_frame_ms": Array(frame_ms.slice(0, mini(frame_i, FRAMES))),
		"crash_frame_ms": crash_frame_ms,
		"inputs": inputs,
		"collisions": collisions,
		"events": events,
		"physics_state": physics_state,
		"settings_graphics": Settings.data.get("graphics", {}),
		"settings_gameplay": Settings.data.get("gameplay", {}),
		"static_memory_mb": snappedf(OS.get_static_memory_usage() / 1048576.0, 0.1),
		"video_memory_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
	}
	rep.merge(extra, true)
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "user://rcpark_diag_%s.json" % stamp
	var result := SafeStore.write_json(path, rep)
	# Even if storage is full, the user can copy the in-memory report.
	result["text"] = JSON.stringify(rep, "  ")
	return result
