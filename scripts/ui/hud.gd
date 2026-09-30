class_name HUD
extends Control
## Minimal in-flight UI: two sticks, essential telemetry, and the few buttons a
## pilot needs mid-flight. Everything else lives in pause/settings.

signal action(name: String)
signal orbit(relative: Vector2)
signal zoom(factor: float)

var sticks: TouchSticks
var telem: Label
var telem_panel: PanelContainer
var toast: Label
var toast_t := 0.0
var info: Label
var dmg_label: Label
var land_panel: PanelContainer
var land_label: Label
var land_t := 0.0
var trick_label: Label
var trick_t := 0.0
var wind_arrow: Control
var btn := {}
var fps_label: Label
var ac: Aircraft
var cam: Camera3D
var orbit_pad: OrbitGesture

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UITheme.theme()
	sticks = TouchSticks.new()
	add_child(sticks)
	sticks.configure()
	orbit_pad = OrbitGesture.new()
	orbit_pad.hint = "ORBIT: drag here  /  pinch to zoom"
	orbit_pad.visible = false
	orbit_pad.orbit.connect(func(relative): orbit.emit(relative))
	orbit_pad.zoom.connect(func(factor): zoom.emit(factor))
	add_child(orbit_pad)
	# telemetry
	telem_panel = PanelContainer.new()
	telem_panel.add_theme_stylebox_override("panel", UITheme.sb(Color(0.03, 0.04, 0.05, 0.45), 12, 0, Color(0, 0, 0, 0), 10))
	telem_panel.position = Vector2(24, 18)
	telem_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(telem_panel)
	telem = UITheme.label("", 19)
	telem.add_theme_constant_override("line_spacing", -2)
	telem_panel.add_child(telem)
	wind_arrow = Control.new()
	wind_arrow.custom_minimum_size = Vector2(56, 56)
	wind_arrow.size = Vector2(56, 56)
	wind_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wind_arrow.draw.connect(_draw_wind)
	add_child(wind_arrow)
	dmg_label = UITheme.label("", 18, Color(1.0, 0.62, 0.45))
	dmg_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	dmg_label.add_theme_constant_override("shadow_offset_y", 2)
	dmg_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dmg_label)
	toast = UITheme.label("", 26)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.position = Vector2(0, 80)
	toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	toast.add_theme_constant_override("shadow_offset_y", 2)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast)
	info = UITheme.label("", 24)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	info.add_theme_constant_override("shadow_offset_y", 2)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(info)
	trick_label = UITheme.label("", 22, UITheme.ACCENT)
	trick_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trick_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	trick_label.add_theme_constant_override("shadow_offset_y", 2)
	trick_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(trick_label)
	land_panel = PanelContainer.new()
	land_panel.add_theme_stylebox_override("panel", UITheme.sb(Color(0.03, 0.04, 0.05, 0.62), 14, 1, Color(1, 1, 1, 0.1), 14))
	land_panel.visible = false
	land_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(land_panel)
	land_label = UITheme.label("", 19)
	land_panel.add_child(land_label)
	fps_label = UITheme.label("", 15, Color(0.7, 1.0, 0.7))
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fps_label)
	# buttons
	for def in [["pause", "II"], ["camera", "CAM"], ["rewind", "-5 s"], ["replay", "REPLAY"],
			["engine", "ENGINE"], ["flaps", "FLAPS"], ["gear", "GEAR"], ["reset", "RESET"]]:
		var b := TouchButton.new(def[1], Vector2(104, 62))
		b.tapped.connect(func(): action.emit(def[0]))
		add_child(b)
		btn[def[0]] = b
	btn["pause"].custom_minimum_size = Vector2(70, 62)
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	var s := size
	if s.x < 10:
		return
	var sa := UITheme.safe_area(self)
	var right := sa.end.x - 18.0
	var top := sa.position.y + 16.0
	var x := right
	for n in ["pause", "camera", "rewind", "replay"]:
		var b: TouchButton = btn[n]
		b.size = b.custom_minimum_size
		x -= b.size.x
		b.position = Vector2(x, top)
		x -= 10.0
	var y := top + 84.0
	for n in ["engine", "flaps", "gear", "reset"]:
		var b2: TouchButton = btn[n]
		b2.size = b2.custom_minimum_size
		b2.position = Vector2(right - b2.size.x, y)
		if b2.visible: y += b2.size.y + 10.0
	orbit_pad.position = Vector2(sa.position.x + sa.size.x * 0.30, top + 136.0)
	orbit_pad.size = Vector2(sa.size.x * 0.40, maxf(65.0, sa.size.y * 0.22))
	telem.add_theme_font_size_override("font_size", 22 if Settings.g("controls", "large_telemetry", false) else 19)
	telem_panel.position = Vector2(sa.position.x + 20.0, top)
	wind_arrow.position = Vector2(sa.position.x + 24.0, top + 150.0)
	dmg_label.position = Vector2(sa.position.x + 90.0, top + 160.0)
	toast.size = Vector2(s.x, 40)
	toast.position = Vector2(0, top + 70.0)
	info.size = Vector2(s.x, 40)
	info.position = Vector2(0, top + 6.0)
	trick_label.size = Vector2(s.x, 40)
	trick_label.position = Vector2(0, top + 110.0)
	land_panel.position = Vector2(s.x * 0.5 - 170.0, s.y * 0.3)
	fps_label.position = Vector2(sa.position.x + 20.0, sa.end.y - 28.0)

func bind(aircraft: Aircraft, camera: Camera3D) -> void:
	ac = aircraft
	cam = camera
	btn["flaps"].visible = ac.has_flaps()
	btn["gear"].visible = ac.has_retracts()
	_update_buttons()
	_layout()

func show_toast(t: String, dur := 2.2) -> void:
	toast.text = t
	toast_t = dur

func show_trick(t: String) -> void:
	trick_label.text = t
	trick_t = 2.5

func show_landing(text: String) -> void:
	land_label.text = text
	land_panel.visible = true
	land_panel.reset_size()
	land_panel.position = Vector2(size.x * 0.5 - land_panel.size.x * 0.5, size.y * 0.24)
	land_t = 6.0

func _update_buttons() -> void:
	if ac == null:
		return
	var fl := int(round(ac.flap_cmd * 2.0))
	(btn["flaps"] as TouchButton).set_text("FLAPS", ["UP", "HALF", "FULL"][clampi(fl, 0, 2)])
	(btn["flaps"] as TouchButton).toggled_on = fl > 0
	(btn["gear"] as TouchButton).set_text("GEAR", "DOWN" if ac.gear_down else "UP")
	var run := ac.engines_running()
	var elec := ac.is_electric()
	(btn["engine"] as TouchButton).set_text("MOTOR" if elec else "ENGINE", ("ARMED" if run else "SAFE") if elec else ("RUN" if run else "OFF"))
	(btn["engine"] as TouchButton).toggled_on = run
	for b in btn.values():
		(b as TouchButton).queue_redraw()

func _process(delta: float) -> void:
	if is_instance_valid(cam) and cam is CameraRig:
		orbit_pad.visible = cam.mode == "free"
	if toast_t > 0.0:
		toast_t -= delta
		toast.modulate.a = clampf(toast_t * 2.0, 0.0, 1.0)
	if trick_t > 0.0:
		trick_t -= delta
		trick_label.modulate.a = clampf(trick_t * 2.0, 0.0, 1.0)
	if land_t > 0.0:
		land_t -= delta
		if land_t <= 0.0:
			land_panel.visible = false
	if Settings.g("graphics", "show_fps", false):
		var st := Diag.stats()
		fps_label.text = "%.0f fps  1%%low %.0f  worst %.1f ms  draws %d" % [Engine.get_frames_per_second(), st.get("low1_fps", 0.0), st.get("worst_ms", 0.0), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)]
	else:
		fps_label.text = ""
	if ac == null or not is_instance_valid(ac):
		return
	var t := ac.telemetry()
	var imperial := String(Settings.g("gameplay", "units", "metric")) == "imperial"
	var spd := float(t["airspeed"]) * (2.237 if imperial else 3.6)
	var alt := float(t["alt"]) * (3.281 if imperial else 1.0)
	var alt_text := ("%.0f %s AGL" % [alt, "ft" if imperial else "m"]) if t.get("alt_valid", false) else "— AGL"
	var lines := "%3.0f %s   %s\nTHR %3.0f%%   %5.0f RPM" % [spd, "mph" if imperial else "km/h", alt_text, float(t["throttle"]) * 100.0, float(t["rpm"])]
	if t["electric"]:
		lines += "\n%.1f V  %.0f%%  %.0f A" % [float(t["volts"]), float(t["soc"]) * 100.0, ac.total_current]
	else:
		lines += "\nFUEL %.0f%%" % (float(t["fuel"]) * 100.0)
	lines += "   " + String(ac.assist).to_upper()
	telem.text = lines
	# damage summary
	var dmg := []
	for c in ac.comps:
		if c["detached"]:
			dmg.append(_pretty(String(c["id"])) + " gone")
		elif float(c["hp"]) < 0.6:
			dmg.append(_pretty(String(c["id"])) + " damaged")
	dmg_label.text = "\n".join(dmg.slice(0, 4))
	wind_arrow.queue_redraw()
	if Engine.get_process_frames() % 10 == 0:
		_update_buttons()

func _pretty(id: String) -> String:
	var s := id.replace("wing0_", "wing ").replace("tip0_", "wingtip ").replace("ail0_", "aileron ").replace("flap0_", "flap ")
	s = s.replace("_L", " L").replace("_R", " R").replace("tail_boom", "tail").replace("prop0", "prop").replace("gear", "gear ")
	var parts := s.split("_")
	return parts[0].capitalize() if parts.size() > 0 else s

func _draw_wind() -> void:
	if Game.wind == null or cam == null:
		return
	var w: Vector3 = Game.wind.sample(Vector3(0, 5, 0))
	var c := wind_arrow.size * 0.5
	wind_arrow.draw_circle(c, 26, Color(0, 0, 0, 0.35))
	if w.length() < 0.3:
		wind_arrow.draw_string(get_theme_default_font(), Vector2(8, 34), "CALM", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.8))
		return
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var right := cam.global_transform.basis.x
	right.y = 0
	right = right.normalized()
	var d2 := Vector2(w.dot(right), -w.dot(fwd)).normalized()
	var tip := c + d2 * 20.0
	var tail := c - d2 * 20.0
	wind_arrow.draw_line(tail, tip, UITheme.ACCENT2, 4.0, true)
	var n := Vector2(-d2.y, d2.x)
	wind_arrow.draw_colored_polygon(PackedVector2Array([tip + d2 * 4.0, tip - d2 * 8.0 + n * 7.0, tip - d2 * 8.0 - n * 7.0]), UITheme.ACCENT2)
	wind_arrow.draw_string(get_theme_default_font(), Vector2(0, 70), Game.wind.describe(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.85))

func release_controls() -> void:
	if is_instance_valid(orbit_pad): orbit_pad.release_all()
	if is_instance_valid(sticks):
		sticks.release_all()
	for child in get_children():
		if child is TouchButton:
			child.release()
