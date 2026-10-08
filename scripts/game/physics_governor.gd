class_name PhysicsGovernor
extends RefCounted
## Lowers the physics tick rate (120 -> 90 -> 60 Hz) while the aircraft is high above the ground and the CPU
## is what limits the frame rate. Measured with tests/phys_rate_probe.gd: the air model gives the same roll and
## pitch responses within a few percent at 120/90/60 Hz, but wheel contact and settling do not (60 Hz leaves
## small residual damage at rest), so the rate always returns to 120 Hz near the ground and in a crash.

const FULL_HZ := 120
const STEPS := [120, 90, 60]
const LOW_AGL := 6.0     # at or below this the rate is forced back to 120 Hz
const HIGH_AGL := 10.0   # the rate may only drop above this (hysteresis against bouncing around the threshold)

var hz := FULL_HZ
var air_level := 0          # index into STEPS the governor wants while airborne
var budget := 1.0 / 60.0
var reason := "initial"
var _elapsed := 0.0
var _samples := 0
var _cpu := 0.0
var _healthy := 0.0
var _cooldown := 0.0
var _recovery_delay := 12.0
var _probe_age := 100.0

func configure(fps: int) -> void:
	budget = 1.0 / float(fps if fps > 0 else 60)
	reset()

func reset() -> void:
	_elapsed = 0.0
	_samples = 0
	_cpu = 0.0
	_healthy = 0.0
	_cooldown = 0.0

## Call once per rendered frame. `cpu_seconds` is the CPU time of the whole frame (script and physics, not GPU
## waits). `agl` is the height above the nearest ground; `grounded` is true on the wheels, when crashed or
## when a menu or replay is showing. Returns the tick rate to use, which changes only when this returns a
## value different from the previous call.
func update(delta: float, cpu_seconds: float, agl: float, grounded: bool) -> int:
	if grounded or agl <= LOW_AGL:
		hz = FULL_HZ
		reset()
		return hz
	if not is_finite(delta) or delta <= 0.0 or delta > 0.25:
		reset()
		return hz
	if agl < HIGH_AGL and hz == FULL_HZ:
		return hz
	if hz != STEPS[air_level]:
		hz = STEPS[air_level]
		reset()
	_elapsed += delta
	_samples += 1
	_cpu += maxf(cpu_seconds, 0.0)
	_cooldown = maxf(0.0, _cooldown - delta)
	_probe_age += delta
	if _elapsed < 1.5:
		return hz
	var avg := _elapsed / float(_samples)
	var cpu := _cpu / float(_samples)
	var window := _elapsed
	_elapsed = 0.0
	_samples = 0
	_cpu = 0.0
	# Slow frames where the CPU is the main cost: drop a step. Slow frames that are the GPU's problem are for
	# the resolution scaler to handle.
	if avg > budget * 1.12 and cpu >= avg * 0.55:
		_healthy = 0.0
		if _cooldown <= 0.0 and air_level < STEPS.size() - 1:
			if _probe_age < 20.0:
				_recovery_delay = minf(96.0, _recovery_delay * 2.0)
			air_level += 1
			hz = STEPS[air_level]
			_cooldown = 3.0
			reason = "CPU over budget; physics at %d Hz while high" % hz
		return hz
	# comfortably inside the budget: probe one step back up, rarely
	if avg <= budget * 1.06 and cpu <= budget * 0.6:
		_healthy += window
	else:
		_healthy = 0.0
	if air_level > 0 and _healthy >= _recovery_delay and _cooldown <= 0.0:
		air_level -= 1
		hz = STEPS[air_level]
		_healthy = 0.0
		_probe_age = 0.0
		_cooldown = 3.0
		reason = "CPU healthy; physics back up to %d Hz" % hz
	return hz
