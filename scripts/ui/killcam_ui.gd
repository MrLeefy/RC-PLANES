class_name KillcamUI
extends Control
## Touch-first transport. Scrubbing always pauses, and orbit owns only background
## gestures: neither transport buttons nor the slider can become camera drags.
signal action(name: String, value: float)
signal orbit(relative: Vector2)
signal zoom(factor: float)

var phase := ""
var title: Label
var sub: Label
var live_box: HBoxContainer
var bar: PanelContainer
var slider: HSlider
var play_btn: Button
var speed_btn: Button
var view_btn: Button
var skip_btn: Button
var end_panel: PanelContainer
var end_text: Label
var resume_btn: Button
var gesture: OrbitGesture
var gesture_hint: Label
var time_label: Label
var transport_row: HBoxContainer
var end_row: HBoxContainer
var speeds := [0.1, 0.25, 0.5, 1.0, 2.0]
var speed_i := 3
var _scrubbing := false
var summary := ""
var impact_fraction := -1.0
var current_view := "cinematic"

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UITheme.theme()
	gesture = OrbitGesture.new()
	gesture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gesture.orbit.connect(func(relative): orbit.emit(relative))
	gesture.zoom.connect(func(factor): zoom.emit(factor))
	add_child(gesture)
	title = UITheme.label("", 40, Color(1.0, 0.50, 0.20))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_shadow_color", Color(0,0,0,0.85))
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	sub = UITheme.label("", 22)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub.add_theme_color_override("font_shadow_color", Color(0,0,0,0.8))
	sub.add_theme_constant_override("shadow_offset_y", 2)
	add_child(sub)
	gesture_hint = UITheme.label("Drag to orbit  ·  Pinch to inspect the wreck", 20, UITheme.TEXT)
	gesture_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gesture_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gesture_hint.add_theme_color_override("font_shadow_color", Color(0,0,0,0.85))
	gesture_hint.add_theme_constant_override("shadow_offset_y", 2)
	add_child(gesture_hint)
	live_box = HBoxContainer.new()
	live_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var keep := UITheme.button("KEEP WATCHING", 270)
	keep.pressed.connect(func(): action.emit("keep", 0.0))
	live_box.add_child(keep)
	add_child(live_box)
	skip_btn = UITheme.accent_button("SKIP  >>", 160, 23)
	skip_btn.pressed.connect(func(): action.emit("skip", 0.0))
	add_child(skip_btn)
	bar = PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UITheme.sb(Color(0.035,0.045,0.06,0.95), 18, 1, Color(1,1,1,0.13), 18))
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 4)
	bar.add_child(layout)
	time_label = UITheme.label("", 19, UITheme.DIM)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(time_label)
	transport_row = HBoxContainer.new()
	layout.add_child(transport_row)
	play_btn = UITheme.button("PAUSE", 112, 22)
	play_btn.pressed.connect(func(): action.emit("playpause", 0.0))
	transport_row.add_child(play_btn)
	slider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.001
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(180, 64)
	slider.drag_started.connect(func():
		_scrubbing = true
		action.emit("seek", slider.value))
	slider.drag_ended.connect(func(_changed):
		action.emit("seek", slider.value)
		_scrubbing = false)
	slider.value_changed.connect(func(value):
		if _scrubbing: action.emit("seek", value))
	slider.draw.connect(_draw_impact)
	transport_row.add_child(slider)
	speed_btn = UITheme.button("1x", 84, 22)
	speed_btn.pressed.connect(_cycle_speed)
	transport_row.add_child(speed_btn)
	view_btn = UITheme.button("CINEMATIC", 162, 20)
	view_btn.pressed.connect(func(): action.emit("view", 0.0))
	transport_row.add_child(view_btn)
	resume_btn = UITheme.accent_button("RESUME", 150, 22)
	resume_btn.pressed.connect(func(): action.emit("resume", 0.0))
	transport_row.add_child(resume_btn)
	add_child(bar)
	end_panel = PanelContainer.new()
	var end_layout := VBoxContainer.new()
	end_layout.add_theme_constant_override("separation", 12)
	end_panel.add_child(end_layout)
	end_text = UITheme.label("", 21)
	end_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	end_layout.add_child(end_text)
	end_row = HBoxContainer.new()
	end_row.alignment = BoxContainer.ALIGNMENT_CENTER
	for item in [["again","WATCH AGAIN"],["rewind","REWIND 5 s"],["repair","REPAIR & FLY"],["hangar","HANGAR"]]:
		var b := UITheme.accent_button(item[1], 185, 22) if item[0] == "repair" else UITheme.button(item[1], 172, 21)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name: String = item[0]
		b.pressed.connect(func(): action.emit(name, 0.0))
		end_row.add_child(b)
	end_layout.add_child(end_row)
	add_child(end_panel)
	resized.connect(_layout)
	set_phase("")

func _layout() -> void:
	if not is_instance_valid(end_panel): return
	var safe := UITheme.safe_area(self)
	var cx := safe.position.x + safe.size.x * 0.5
	title.position = safe.position + Vector2(20, 28)
	title.size = Vector2(safe.size.x - 40, 56)
	sub.position = safe.position + Vector2(80, 84)
	sub.size = Vector2(safe.size.x - 160, 60)
	gesture_hint.position = safe.position + Vector2(20, 150)
	gesture_hint.size = Vector2(safe.size.x - 40, 30)
	live_box.size = Vector2(safe.size.x, 64)
	live_box.position = Vector2(safe.position.x, safe.end.y - 98)
	skip_btn.size = skip_btn.get_combined_minimum_size()
	skip_btn.position = Vector2(safe.end.x - skip_btn.size.x - 24, safe.position.y + safe.size.y * 0.43)
	bar.size = Vector2(minf(safe.size.x - 48, 1370), 108)
	bar.position = Vector2(cx - bar.size.x * 0.5, safe.end.y - bar.size.y - 24)
	end_panel.size = Vector2(minf(safe.size.x - 64, 1150), 0)
	end_panel.custom_minimum_size.x = minf(safe.size.x - 64, 1150)
	end_panel.reset_size()
	# Re-evaluate after the container wraps the summary at its new width.
	end_panel.position = Vector2(cx - end_panel.size.x * 0.5, maxf(safe.position.y + 196, bar.position.y - end_panel.size.y - 16))

func set_phase(value: String) -> void:
	phase = value
	visible = value != ""
	_scrubbing = false
	gesture.release_all()
	live_box.visible = value == "live"
	skip_btn.visible = value in ["live", "replay"]
	bar.visible = value in ["replay", "instant", "end"]
	end_panel.visible = value == "end"
	resume_btn.visible = value == "instant"
	match value:
		"live":
			title.text = "CRASH / LIVE AFTERMATH"
			sub.text = summary
		"replay":
			title.text = "KILL CAM"
			sub.text = "Your impact is marked on the timeline. Scrub to inspect any moment."
		"instant":
			title.text = "INSTANT REPLAY"
			sub.text = "Flight is paused. Resume returns to your saved aircraft state."
		"end":
			title.text = "CRASH REVIEW"
			sub.text = "Inspect, replay, rewind or get straight back in the air."
			end_text.text = summary
		_:
			title.text = ""
			sub.text = ""
	play_btn.text = "PAUSE"
	set_view_name(current_view)
	_layout()
	_layout.call_deferred()

func set_playing(on: bool) -> void:
	play_btn.text = "PAUSE" if on else "PLAY"

func set_progress(fraction: float) -> void:
	if not _scrubbing: slider.set_value_no_signal(fraction)

func set_view_name(name: String) -> void:
	current_view = name
	view_btn.text = name.to_upper()
	gesture.visible = phase in ["replay", "instant", "end"] and name in ["free", "orbit", "part"]
	gesture_hint.visible = gesture.visible

func set_timing(time: float, start: float, end: float, impact: float) -> void:
	var duration := maxf(0.0, end - start)
	time_label.text = "%s / %s" % [_clock(time - start), _clock(duration)]
	impact_fraction = -1.0
	if impact >= start and impact <= end and duration > 0.0:
		impact_fraction = (impact - start) / duration
		time_label.text += "    ·    IMPACT " + _clock(impact - start)
	slider.queue_redraw()

func _clock(time: float) -> String:
	var t := maxf(time, 0.0)
	return "%d:%04.1f" % [int(t) / 60, fmod(t, 60.0)]

func _draw_impact() -> void:
	if impact_fraction < 0.0: return
	# Slider handles have a 14-pixel half-width in UITheme.
	var x := 14.0 + impact_fraction * maxf(0, slider.size.x - 28.0)
	slider.draw_colored_polygon(PackedVector2Array([Vector2(x-6,5), Vector2(x+6,5), Vector2(x,14)]), UITheme.ACCENT)
	slider.draw_line(Vector2(x,16), Vector2(x,slider.size.y-8), Color(1,0.55,0.12,0.6), 2.0)

func _cycle_speed() -> void:
	speed_i = (speed_i + 1) % speeds.size()
	var speed: float = speeds[speed_i]
	speed_btn.text = "%.2gx" % speed
	action.emit("speed", speed)

func reset_speed() -> void:
	speed_i = 3
	speed_btn.text = "1x"

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		_scrubbing = false
		if is_instance_valid(gesture): gesture.release_all()