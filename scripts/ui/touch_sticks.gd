class_name TouchSticks
extends Control
## Two RC-transmitter sticks with strict pointer ownership:
## each stick owns exactly one touch index; extra fingers are ignored; lost focus,
## cancelled touches and app pauses release everything (no stale inputs).
## The throttle axis does not spring back (ratchet), like a real transmitter.

var stick_mode := 2
var scale_f := 1.0
var opacity := 0.55
var floating := false
var left_handed := false
var sticks := [
	{"idx": -1, "center": Vector2.ZERO, "home": Vector2.ZERO, "val": Vector2.ZERO, "start": Vector2.ZERO, "thr0": 0.0},
	{"idx": -1, "center": Vector2.ZERO, "home": Vector2.ZERO, "val": Vector2.ZERO, "start": Vector2.ZERO, "thr0": 0.0}]
var throttle := 0.0
var radius := 110.0
var safe := Rect2()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)
	_layout()

func configure() -> void:
	stick_mode = int(Settings.g("controls", "mode", 2))
	scale_f = float(Settings.g("controls", "stick_size", 1.0))
	opacity = float(Settings.g("controls", "opacity", 0.55))
	floating = bool(Settings.g("controls", "floating", false))
	left_handed = bool(Settings.g("controls", "left_handed", false))
	_layout()

func _layout() -> void:
	var s := size
	if s.x < 10:
		return
	safe = UITheme.safe_area(self)
	var desired := clampf(safe.size.y * 0.17 * scale_f, 70.0, 190.0)
	radius = minf(desired, minf(safe.size.x * 0.23 - 36.0, safe.size.y * 0.30))
	radius = maxf(radius, 32.0)
	var m := radius + 40.0
	sticks[0]["home"] = Vector2(safe.position.x + m, safe.end.y - m)
	sticks[1]["home"] = Vector2(safe.end.x - m, safe.end.y - m)
	# Rotating/resizing while holding a stick must not retain an off-screen owner.
	release_all()
	for st in sticks:
		if int(st["idx"]) < 0:
			st["center"] = st["home"]
	queue_redraw()

func _zone(p: Vector2) -> int:
	if p.y < size.y * 0.22:
		return -1
	return 0 if p.x < size.x * 0.5 else 1

func _throttle_stick() -> int:
	var s := 0 if stick_mode == 2 else 1
	if left_handed:
		s = 1 - s
	return s

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.canceled:
			for i in 2:
				if int(sticks[i]["idx"]) == t.index:
					_release(i)
			accept_event()
			return
		if t.pressed:
			var z := _zone(t.position)
			if z < 0:
				return
			var st: Dictionary = sticks[z]
			if int(st["idx"]) >= 0:
				return   # stick already owned: ignore third finger
			st["idx"] = t.index
			st["start"] = t.position
			st["thr0"] = throttle
			if floating:
				st["center"] = t.position
			_update_stick(z, t.position)
			accept_event()
		else:
			for i in 2:
				if int(sticks[i]["idx"]) == t.index:
					_release(i)
					accept_event()
	elif event is InputEventScreenDrag:
		var dr := event as InputEventScreenDrag
		for i in 2:
			if int(sticks[i]["idx"]) == dr.index:
				_update_stick(i, dr.position)
				accept_event()

func _update_stick(i: int, p: Vector2) -> void:
	var st: Dictionary = sticks[i]
	var c: Vector2 = st["center"]
	var d := (p - c) / radius
	var v := Vector2(clampf(d.x, -1.0, 1.0), clampf(d.y, -1.0, 1.0))
	if i == _throttle_stick():
		# throttle: relative, non-centering
		var dy := (p.y - (st["start"] as Vector2).y) / (radius * 2.0)
		throttle = clampf(float(st["thr0"]) - dy, 0.0, 1.0)
		v.y = 1.0 - throttle * 2.0
	st["val"] = v
	queue_redraw()

func _release(i: int) -> void:
	var st: Dictionary = sticks[i]
	st["idx"] = -1
	var v: Vector2 = st["val"]
	v.x = 0.0
	if i != _throttle_stick():
		v.y = 0.0
	st["val"] = v
	st["center"] = st["home"]
	queue_redraw()

func release_all() -> void:
	for i in 2:
		_release(i)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_VISIBILITY_CHANGED]:
		release_all()

## Returns roll, pitch, yaw (-1..1, pitch + = nose up) and throttle 0..1
func values() -> Dictionary:
	var ts := _throttle_stick()
	var other := 1 - ts
	var tv: Vector2 = sticks[ts]["val"]
	var ov: Vector2 = sticks[other]["val"]
	if stick_mode == 2:
		return {"roll": ov.x, "pitch": ov.y, "yaw": tv.x, "throttle": throttle}
	# mode 1: throttle + aileron on one stick, elevator + rudder on the other
	return {"roll": tv.x, "pitch": ov.y, "yaw": ov.x, "throttle": throttle}

func set_throttle(t: float) -> void:
	throttle = clampf(t, 0.0, 1.0)
	var ts := _throttle_stick()
	var v: Vector2 = sticks[ts]["val"]
	v.y = 1.0 - throttle * 2.0
	sticks[ts]["val"] = v
	queue_redraw()

func _draw() -> void:
	var a := opacity
	for i in 2:
		var st: Dictionary = sticks[i]
		var c: Vector2 = st["center"]
		var v: Vector2 = st["val"]
		draw_circle(c, radius + 8.0, Color(0, 0, 0, 0.18 * a))
		draw_arc(c, radius, 0, TAU, 64, Color(1, 1, 1, 0.55 * a), 3.0, true)
		draw_line(c - Vector2(radius, 0), c + Vector2(radius, 0), Color(1, 1, 1, 0.18 * a), 2.0)
		draw_line(c - Vector2(0, radius), c + Vector2(0, radius), Color(1, 1, 1, 0.18 * a), 2.0)
		if i == _throttle_stick():
			# throttle ladder
			for k in 11:
				var y := c.y + radius - k * radius * 0.2
				var w := 10.0 if k % 5 == 0 else 5.0
				draw_line(Vector2(c.x - radius - 14 - w, y), Vector2(c.x - radius - 14, y), Color(1, 1, 1, 0.4 * a), 2.0)
			var ty := c.y + radius - throttle * radius * 2.0
			draw_rect(Rect2(Vector2(c.x - radius - 20, ty), Vector2(6, c.y + radius - ty)), Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.8 * a))
		var kp := c + v * radius
		var owned := int(st["idx"]) >= 0
		draw_circle(kp, radius * 0.32, Color(1, 1, 1, (0.55 if owned else 0.35) * a))
		draw_arc(kp, radius * 0.32, 0, TAU, 40, Color(1, 1, 1, 0.9 * a), 2.0, true)

func has_active_touches() -> bool:
	return int(sticks[0]["idx"]) >= 0 or int(sticks[1]["idx"]) >= 0
