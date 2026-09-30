class_name TouchButton
extends Control
## Multi-touch aware on-screen button (works while other fingers hold sticks).
## Uses its own touch index tracking instead of the single emulated mouse pointer.

signal tapped
signal held(down: bool)

var text := ""
var sub := ""
var active := false
var toggled_on := false
var accent := false
var _idx := -1
var font_size := 20

func _init(t := "", sz := Vector2(92, 64)) -> void:
	text = t
	custom_minimum_size = sz
	size = sz
	mouse_filter = Control.MOUSE_FILTER_STOP

func _input(event: InputEvent) -> void:
	# _gui_input may stop receiving this pointer after it leaves the control.
	if event is InputEventScreenTouch and event.index == _idx and (event.canceled or not event.pressed):
		var local := get_global_transform_with_canvas().affine_inverse() * event.position
		_finish_touch(not event.canceled and is_visible_in_tree() and Rect2(Vector2.ZERO, size).grow(12).has_point(local))
		get_viewport().set_input_as_handled()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.canceled:
			if event.index == _idx:
				release()
			return
		if event.pressed and _idx < 0:
			_idx = event.index
			active = true
			held.emit(true)
			queue_redraw()
			accept_event()
		elif not event.pressed and event.index == _idx:
			_finish_touch(Rect2(Vector2.ZERO, size).grow(12).has_point(event.position))
			accept_event()

func _finish_touch(activate: bool) -> void:
	release()
	if activate:
		tapped.emit()
		Sfx.ui("click", 0.5)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_EXIT_TREE]:
		release()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		release()

func release() -> void:
	if _idx >= 0:
		_idx = -1
		active = false
		held.emit(false)
		queue_redraw()

func set_text(t: String, s := "") -> void:
	text = t
	sub = s
	queue_redraw()

func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var bg := Color(0.05, 0.06, 0.08, 0.55)
	if toggled_on:
		bg = Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.6)
	if active:
		bg = Color(1, 1, 1, 0.35)
	if accent and not active:
		bg = Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.85)
	var s := UITheme.sb(bg, 14, 1, Color(1, 1, 1, 0.22))
	draw_style_box(s, r)
	var f := get_theme_default_font()
	var fs := font_size
	var col := Color(0.08, 0.06, 0.04) if accent else Color(1, 1, 1, 0.95)
	var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
	var y := size.y * 0.5 + ts.y * 0.3 - (7.0 if sub != "" else 0.0)
	draw_string(f, Vector2((size.x - ts.x) * 0.5, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	if sub != "":
		var ss := f.get_string_size(sub, HORIZONTAL_ALIGNMENT_CENTER, -1, 14)
		draw_string(f, Vector2((size.x - ss.x) * 0.5, y + 18), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(col.r, col.g, col.b, 0.75))