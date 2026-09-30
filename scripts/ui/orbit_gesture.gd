class_name OrbitGesture
extends Control
## Gesture ownership is acquired ONLY by a press on this Control. Sliders,
## buttons and sticks above it retain their own touches; an unrelated third
## finger never joins a pinch. All ownership is cleared on cancellation/hide.
signal orbit(relative: Vector2)
signal zoom(factor: float)
var points: Dictionary = {}
var hint := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visibility_changed.connect(release_all)

func release_all() -> void:
	points.clear()

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_EXIT_TREE]:
		release_all()

func _input(event: InputEvent) -> void:
	# A release outside the rectangle must also release the original owner.
	if event is InputEventScreenTouch and (event.canceled or not event.pressed) and points.has(event.index):
		points.erase(event.index)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.canceled or not event.pressed:
			points.erase(event.index)
		elif points.size() < 2 and not points.has(event.index):
			points[event.index] = event.position
		accept_event()
	elif event is InputEventScreenDrag and points.has(event.index):
		var previous: Vector2 = points[event.index]
		if points.size() == 2:
			var keys := points.keys()
			var before := (points[keys[0]] as Vector2).distance_to(points[keys[1]])
			points[event.index] = event.position
			var after := (points[keys[0]] as Vector2).distance_to(points[keys[1]])
			if before > 8.0 and after > 8.0:
				zoom.emit(clampf(before / after, 0.75, 1.33))
		else:
			points[event.index] = event.position
			orbit.emit(event.position - previous)
		accept_event()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom.emit(0.9)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom.emit(1.1)
			accept_event()

func _draw() -> void:
	if not hint.is_empty():
		var f := get_theme_default_font()
		var w := f.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string(f, Vector2((size.x - w) * 0.5, 25), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1,1,1,0.8))
