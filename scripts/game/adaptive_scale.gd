class_name AdaptiveScale
extends RefCounted
## The presentation clock includes the FPS limiter. Recovery therefore probes
## upward at healthy *capped* frame times, rather than demanding uncapped FPS.

var scale := 0.85
var ceiling := 0.85
var budget := 1.0 / 60.0
var reason := "initial"
var warmup := 4.0
var elapsed := 0.0
var samples := 0
var healthy := 0.0
var cooldown := 0.0
var recovery_delay := 6.0
var probe_age := 100.0
var cpu_seconds := 0.0

func configure(requested: float, fps: int, ultra := false) -> void:
	ceiling = clampf(maxf(requested, 0.95) if ultra else requested, 0.5, 1.0)
	scale = ceiling
	budget = 1.0 / float(fps if fps > 0 else 60)
	recovery_delay = 6.0
	reset_window()

func reset_window() -> void:
	warmup = 4.0
	elapsed = 0.0
	samples = 0
	healthy = 0.0
	cpu_seconds = 0.0
	cooldown = 0.0
	probe_age = 100.0

func update(delta: float, physics_seconds := 0.0) -> bool:
	if not is_finite(delta) or delta <= 0.0 or delta > 0.25:
		reset_window()
		return false
	if warmup > 0.0:
		warmup -= delta
		return false
	elapsed += delta
	samples += 1
	cpu_seconds += maxf(physics_seconds, 0.0)
	cooldown = maxf(0.0, cooldown - delta)
	probe_age += delta
	if elapsed < 2.0:
		return false
	var window := elapsed
	var avg := elapsed / float(samples)
	var cpu := cpu_seconds / float(samples)
	elapsed = 0.0
	samples = 0
	cpu_seconds = 0.0
	if avg > budget * 1.15:
		healthy = 0.0
		# Do not keep reducing pixel quality to fix an identified physics bottleneck.
		if cpu >= budget * 0.85 or cooldown > 0.0 or scale <= 0.5:
			return false
		if probe_age < 5.0:
			recovery_delay = minf(48.0, recovery_delay * 2.0)
		scale = maxf(0.5, snappedf(scale - 0.05, 0.001))
		cooldown = 4.0
		reason = "over budget; reduce 3D resolution"
		return true
	if avg <= budget * 1.06:
		healthy += window
	else:
		healthy = 0.0
	if healthy >= recovery_delay and cooldown <= 0.0 and scale < ceiling:
		scale = minf(ceiling, snappedf(scale + 0.025, 0.001))
		healthy = 0.0
		probe_age = 0.0
		cooldown = 4.0
		reason = "healthy capped frames; probe sharper 3D resolution"
		return true
	return false