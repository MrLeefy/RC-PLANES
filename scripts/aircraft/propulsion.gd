class_name Propulsion
extends RefCounted
## Physically based power systems. One instance per engine.
## electric: Kv motor + ESC + LiPo pack (shared) + prop (momentum/blade-element fit)
## glow2 / glow4 / gas2: torque-curve IC engine with idle, fuel, start/stall
## edf: spool-lag fan with ram-drag thrust curve, battery draw
## turbine: slow spool, idle thrust, kerosene burn, start sequence
## The RPM shown/heard/animated is the simulated state variable itself.

const RHO := 1.225

var type := "electric"
var d: Dictionary
var pos := Vector3.ZERO
var dir := Vector3(0, 0, -1)
var spin := 1
var D := 0.25
var pitch := 0.15
var blades := 2
var omega := 0.0           # rad/s (prop / fan / spool shaft)
var rpm_frac := 0.0        # edf/turbine normalised spool
var running := false       # IC/turbine running; electric armed
var starting := 0.0        # starter timer
var stall_timer := 0.0
var thrust := 0.0
var torque := 0.0
var current := 0.0
var power := 0.0
var i_rot := 1e-4
var health := 1.0          # prop/fan health multiplier (damage)
var vibration := 0.0
var strike_torque := 0.0   # extra torque from prop hitting things
var mount_ok := true
var wash_v := 0.0          # slipstream velocity (m/s)
var thr_cmd := 0.0
var ct0 := 0.1
var cp0 := 0.045
var jz := 0.8
var blade_k := 1.0
var message := ""

func setup(e: Dictionary) -> void:
	d = e["def"]
	type = String(e["type"])
	pos = e["pos"]
	dir = (e["dir"] as Vector3).normalized()
	spin = int(e["spin"])
	D = maxf(float(e["D"]), 0.02)
	pitch = float(e["pitch"])
	blades = int(e["blades"])
	var pd := clampf(pitch / D, 0.3, 1.2)
	ct0 = 0.075 + 0.04 * pd
	cp0 = 0.02 + 0.04 * pd
	jz = 1.08 * pd + 0.12
	blade_k = [1.0, 1.0, 1.0, 1.22, 1.4, 1.55][clampi(blades, 0, 5)]
	var m_prop := 0.012 * pow(D / 0.25, 2.6) * (float(blades) / 2.0)
	i_rot = m_prop * D * D / 12.0 + 2e-5 * pow(D / 0.25, 3.0)
	if type in ["glow2", "glow4", "gas2"]:
		i_rot *= 2.2  # crank + flywheel effect of the prop hub
	running = type == "electric"  # electric is armed by default (throttle safety handled by controller)

func is_prop() -> bool:
	return type in ["electric", "glow2", "glow4", "gas2"]

func rpm() -> float:
	if type == "edf" or type == "turbine":
		return rpm_frac * float(d.get("rpm_max", 40000.0))
	return omega * 60.0 / TAU

func start_request(throttle: float) -> String:
	if type == "electric" or type == "edf":
		running = not running
		return "Armed" if running else "Disarmed"
	if running:
		running = false
		starting = 0.0
		return "Engine off"
	if type == "turbine":
		if throttle > 0.1:
			return "Throttle to idle to start"
		starting = 3.2
		return "Starting turbine..."
	if throttle > 0.3:
		return "Lower throttle to start"
	starting = 1.2
	return "Starting..."

func kill() -> void:
	running = false
	starting = 0.0

## Main update. v_axial: airflow speed into the disc (m/s, + = forward flight).
## battery: Dictionary {v: loaded voltage, v_nom: nominal voltage}
func step(dt: float, throttle: float, v_axial: float, battery: Dictionary, fuel_ok: bool) -> void:
	thr_cmd = throttle
	current = 0.0
	power = 0.0
	match type:
		"electric": _electric(dt, throttle, v_axial, battery)
		"glow2", "glow4", "gas2": _ic(dt, throttle, v_axial, fuel_ok)
		"edf": _edf(dt, throttle, v_axial, battery)
		"turbine": _turbine(dt, throttle, v_axial, fuel_ok)
	# slipstream induced velocity (momentum theory)
	if is_prop():
		var A := PI * D * D * 0.25
		var t := maxf(thrust, 0.0)
		var va := maxf(v_axial, 0.0)
		var vi := 0.5 * (-va + sqrt(va * va + 2.0 * t / (RHO * A)))
		wash_v = vi * 1.7
	else:
		wash_v = 0.0

func _prop_forces(n: float, v_axial: float) -> Vector2:
	# returns (thrust N, torque Nm)
	if n < 0.05 or health <= 0.0:
		return Vector2(0.0, 0.0)
	var J := clampf(v_axial / (n * D), -0.5, 3.0)
	var jr := J / jz
	var ct := ct0 * (1.0 - jr) * blade_k
	if jr > 1.0:
		ct = ct0 * (1.0 - jr) * 0.6 * blade_k  # windmilling braking region
	var cp := cp0 * maxf(1.0 - 0.28 * jr - 0.1 * jr * jr, 0.12) * blade_k
	var n2 := n * n
	var T := ct * RHO * n2 * pow(D, 4.0)
	var Q := cp * RHO * n2 * pow(D, 5.0) / TAU
	var hm := clampf(health, 0.0, 1.0)
	var eff := 1.0 if hm > 0.7 else (0.85 if hm > 0.35 else 0.4)
	return Vector2(T * eff, Q * (0.7 + 0.3 * eff))

func _electric(dt: float, throttle: float, v_axial: float, battery: Dictionary) -> void:
	var kv := float(d["kv"])
	var ke := 60.0 / (TAU * kv)       # V per rad/s  (= Kt, Nm/A)
	var rm := float(d["rm"])
	var i0 := float(d["i0"])
	var vb := float(battery.get("v", 14.8))
	var thr := clampf(throttle, 0.0, 1.0) if running and mount_ok else 0.0
	thr *= float(battery.get("lvc", 1.0))
	var sub := 4
	var h := dt / sub
	var I := 0.0
	var T := 0.0
	var Qp := 0.0
	for k in sub:
		var n := omega / TAU
		var pf := _prop_forces(n, v_axial)
		T = pf.x
		Qp = pf.y
		var emf := omega * ke
		var vm := thr * vb
		I = (vm - emf) / rm if thr > 0.001 else 0.0
		I = maxf(I, 0.0)
		var qm := ke * maxf(I - i0, 0.0)
		var fric := 0.002 * omega * ke + (0.004 if omega > 1.0 else 0.0)
		omega += (qm - Qp - fric - strike_torque) / i_rot * h
		omega = maxf(omega, 0.0)
	thrust = T
	torque = Qp
	current = I + (i0 if thr > 0.001 else 0.0)
	power = vb * current

func _ic(dt: float, throttle: float, v_axial: float, fuel_ok: bool) -> void:
	var qmax := float(d["qmax"])
	var rp := float(d["rpm_peak"]) * TAU / 60.0
	var rmax := float(d["rpm_max"]) * TAU / 60.0
	var idle := float(d["idle"])
	if starting > 0.0:
		starting -= dt
		# electric starter spins the engine up
		omega = move_toward(omega, 1600.0 * TAU / 60.0, 3000.0 * dt)
		if starting <= 0.0:
			if fuel_ok and throttle < 0.35 and health > 0.0 and mount_ok:
				running = true
				message = "Engine running"
			else:
				message = "Engine didn't catch"
	if not fuel_ok or health <= 0.0 or not mount_ok:
		if running:
			message = "Engine quit" if fuel_ok else "Out of fuel"
		running = false
	var sub := 3
	var h := dt / sub
	var T := 0.0
	var Qp := 0.0
	var qe := 0.0
	for k in sub:
		var n := omega / TAU
		var pf := _prop_forces(n, v_axial)
		T = pf.x
		Qp = pf.y
		var x := omega / rp
		qe = 0.0
		if running:
			var thr := idle + (1.0 - idle) * clampf(throttle, 0.0, 1.0)
			var shape := clampf(1.0 - 0.42 * (x - 1.0) * (x - 1.0), 0.18, 1.0)
			if omega > rmax:
				shape *= maxf(0.0, 1.0 - (omega - rmax) / (rmax * 0.08))
			if type == "glow4":
				shape = clampf(1.0 - 0.3 * (x - 1.0) * (x - 1.0), 0.3, 1.0)  # flatter torque curve
			qe = qmax * pow(thr, 1.15) * shape
		var fric := qmax * (0.02 + 0.035 * x) * (1.0 if running else 2.5) * (1.0 if omega > 0.5 else 0.0)
		omega += (qe - Qp - fric - strike_torque) / i_rot * h
		omega = maxf(omega, 0.0)
	thrust = T
	torque = Qp
	power = qe * omega
	# stall if bogged down (prop strike, too much load)
	if running and omega < rp * 0.11:
		stall_timer += dt
		if stall_timer > 0.25:
			running = false
			message = "Engine stalled"
	else:
		stall_timer = 0.0
	vibration = (0.15 if running else 0.0) * (1.0 + (1.0 - health) * 4.0)

func _edf(dt: float, throttle: float, v_axial: float, battery: Dictionary) -> void:
	var vnom := float(battery.get("v_nom", 22.2))
	var vb := float(battery.get("v", vnom))
	var vf := clampf(vb / vnom, 0.0, 1.15)
	var thr := clampf(throttle, 0.0, 1.0) if running and mount_ok else 0.0
	thr *= float(battery.get("lvc", 1.0))
	var target := sqrt(thr) * vf * (1.0 if health > 0.3 else 0.3)
	var tau := float(d.get("spool", 0.22)) * (1.0 if target > rpm_frac else 1.4)
	rpm_frac += (target - rpm_frac) * clampf(dt / tau, 0.0, 1.0)
	rpm_frac = maxf(rpm_frac, 0.0)
	var t0 := float(d["thrust"]) * rpm_frac * rpm_frac * health
	var vex := float(d["v_exit"]) * maxf(rpm_frac, 0.05)
	thrust = t0 * clampf(1.0 - v_axial / vex, -0.25, 1.0)
	current = float(d["amps"]) * pow(rpm_frac, 3.0) * vf
	power = current * vb
	torque = power / maxf(rpm_frac * float(d["rpm_max"]) * TAU / 60.0, 50.0) * 0.3
	omega = rpm_frac * float(d["rpm_max"]) * TAU / 60.0

func _turbine(dt: float, throttle: float, v_axial: float, fuel_ok: bool) -> void:
	var idle := float(d["idle_frac"])
	if starting > 0.0:
		starting -= dt
		rpm_frac = move_toward(rpm_frac, idle * 0.9, dt * 0.35)
		if starting <= 0.0:
			if fuel_ok and mount_ok:
				running = true
				message = "Turbine running"
	if not fuel_ok or not mount_ok or health <= 0.0:
		if running:
			message = "Flame-out"
		running = false
	var target := 0.0
	if running:
		target = idle + (1.0 - idle) * clampf(throttle, 0.0, 1.0)
	elif starting > 0.0:
		target = rpm_frac
	var tu := float(d["spool_up"]) if target > rpm_frac else float(d["spool_down"])
	# spool rate slower at low rpm (realistic lag)
	var rate := (1.0 / tu) * (0.45 + 0.55 * rpm_frac)
	rpm_frac += clampf(target - rpm_frac, -rate * dt, rate * dt)
	rpm_frac = maxf(rpm_frac, 0.0)
	var x := clampf((rpm_frac - idle * 0.7) / (1.0 - idle * 0.7), 0.0, 1.0)
	var t0 := float(d["thrust"]) * pow(x, 2.2) * health
	var vex := float(d["v_exit"]) * maxf(x, 0.3)
	thrust = t0 * clampf(1.0 - v_axial / vex, 0.0, 1.0)
	power = thrust * 40.0
	omega = rpm_frac * float(d["rpm_max"]) * TAU / 60.0
	torque = 0.0

func fuel_burn_rate() -> float:
	# kg/s
	match type:
		"glow2", "glow4":
			return power / 1000.0 * 1.55 / 3600.0 + (0.00003 if running else 0.0)
		"gas2":
			return power / 1000.0 * 0.55 / 3600.0 + (0.00001 if running else 0.0)
		"turbine":
			if not running:
				return 0.0
			return float(d["burn"]) * (0.22 + 0.78 * rpm_frac * rpm_frac)
	return 0.0

const RUNTIME_FIELDS := ["omega", "rpm_frac", "running", "starting", "health", "mount_ok", "stall_timer",
	"thrust", "torque", "current", "power", "vibration", "strike_torque", "wash_v", "thr_cmd", "message"]

func snapshot() -> Dictionary:
	var result := {}
	for key in RUNTIME_FIELDS:
		result[key] = get(key)
	return result

func restore(s: Dictionary) -> void:
	for key in RUNTIME_FIELDS:
		if s.has(key): set(key, s[key])