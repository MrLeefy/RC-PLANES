class_name SettingsUI
extends Control
## Settings: transmitter profiles (global / per-aircraft / named) with live curve
## preview, touch layout, graphics, audio, gameplay and diagnostics.

signal closed
signal graphics_changed

var aircraft_id := "skylark"
var tabs: TabContainer
var tx_profile_opt: OptionButton
var tx_axes: Dictionary = {}
var curve_views: Dictionary = {}
var per_aircraft_chk: CheckBox
var name_edit: LineEdit
var smooth_slider: HSlider
var content_root: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UITheme.theme()
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.035, 0.045, 0.97)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 40
	root.offset_right = -40
	root.offset_top = 24
	root.offset_bottom = -20
	content_root = root
	add_child(root)
	resized.connect(_layout_safe)
	_layout_safe()
	var top := HBoxContainer.new()
	var title := UITheme.label("SETTINGS", 34)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := UITheme.accent_button("DONE", 180)
	close.pressed.connect(_close)
	top.add_child(close)
	root.add_child(top)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 22)
	root.add_child(tabs)
	_tab_transmitter()
	_tab_controls()
	_tab_graphics()
	_tab_audio()
	_tab_gameplay()
	_tab_about()

func _page(title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 14)
	sc.add_child(vb)
	tabs.add_child(sc)
	return vb

func _row(parent: Control, label_text: String, ctrl: Control, w := 320) -> HBoxContainer:
	var hb := HBoxContainer.new()
	var l := UITheme.label(label_text, 22)
	l.custom_minimum_size = Vector2(w, 0)
	hb.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(ctrl)
	parent.add_child(hb)
	return hb

func _slider(minv: float, maxv: float, step: float, val: float, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = minv
	s.max_value = maxv
	s.step = step
	s.value = val
	s.custom_minimum_size = Vector2(260, 48)
	s.value_changed.connect(cb)
	return s

func _check(text: String, on: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.add_theme_font_size_override("font_size", 22)
	c.toggled.connect(cb)
	return c

# ---------------------------------------------------------------- transmitter
func _profile() -> Dictionary:
	var tx: Dictionary = Settings.data["transmitter"]
	var name := Settings.tx_profile_name_for(aircraft_id)
	if not tx["profiles"].has(name):
		tx["profiles"][name] = Settings.TX_PRESETS["Balanced"].duplicate(true)
	return tx["profiles"][name]

func _tab_transmitter() -> void:
	var vb := _page("Transmitter")
	var hb := HBoxContainer.new()
	hb.add_child(UITheme.label("Profile", 22))
	tx_profile_opt = OptionButton.new()
	tx_profile_opt.custom_minimum_size = Vector2(300, 56)
	tx_profile_opt.item_selected.connect(_on_profile_selected)
	hb.add_child(tx_profile_opt)
	per_aircraft_chk = _check("Only for this aircraft", false, _on_per_aircraft)
	hb.add_child(per_aircraft_chk)
	vb.add_child(hb)
	var hb2 := HBoxContainer.new()
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "New profile name"
	name_edit.custom_minimum_size = Vector2(300, 52)
	hb2.add_child(name_edit)
	var save_btn := UITheme.button("SAVE AS NEW", 200)
	save_btn.pressed.connect(_save_as)
	hb2.add_child(save_btn)
	var del_btn := UITheme.button("DELETE", 140)
	del_btn.pressed.connect(_delete_profile)
	hb2.add_child(del_btn)
	vb.add_child(hb2)
	var hb3 := HBoxContainer.new()
	hb3.add_child(UITheme.label("Presets:", 22))
	for p in Settings.TX_PRESETS.keys():
		var b := UITheme.button(p, 180)
		var pn: String = p
		b.pressed.connect(func(): _apply_preset(pn))
		hb3.add_child(b)
	vb.add_child(hb3)
	var axes_row := HBoxContainer.new()
	axes_row.add_theme_constant_override("separation", 26)
	for ax in ["roll", "pitch", "yaw"]:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(UITheme.label({"roll": "ROLL (aileron)", "pitch": "PITCH (elevator)", "yaw": "YAW (rudder)"}[ax], 22, UITheme.ACCENT))
		var cv := CurveView.new()
		cv.custom_minimum_size = Vector2(200, 150)
		col.add_child(cv)
		curve_views[ax] = cv
		var sl := {}
		for f in [["expo", "Expo", 0.0, 1.0, 0.01], ["rate", "Max travel", 0.2, 1.0, 0.01], ["dz", "Dead zone", 0.0, 0.2, 0.005], ["trim", "Trim", -0.25, 0.25, 0.005]]:
			var key: String = f[0]
			var axn: String = ax
			var lbl := UITheme.label(f[1], 18, UITheme.DIM)
			col.add_child(lbl)
			var s := _slider(f[2], f[3], f[4], 0.0, func(v): _set_axis(axn, key, v))
			col.add_child(s)
			sl[key] = s
		tx_axes[ax] = sl
		axes_row.add_child(col)
	vb.add_child(axes_row)
	smooth_slider = _slider(0.0, 0.3, 0.01, 0.05, func(v): _profile()["smoothing"] = v)
	_row(vb, "Control smoothing (feel only)", smooth_slider)
	vb.add_child(UITheme.label("Assist level (Arcade / Sport / Expert) is separate: set it in Gameplay. Linear/Direct = exactly linear.", 17, UITheme.DIM))
	_refresh_tx()

func _refresh_tx() -> void:
	var tx: Dictionary = Settings.data["transmitter"]
	tx_profile_opt.clear()
	var names: Array = tx["profiles"].keys()
	var cur := Settings.tx_profile_name_for(aircraft_id)
	for i in names.size():
		tx_profile_opt.add_item(String(names[i]))
		if names[i] == cur:
			tx_profile_opt.select(i)
	per_aircraft_chk.set_pressed_no_signal((tx["per_aircraft"] as Dictionary).has(aircraft_id))
	var p := _profile()
	for ax in ["roll", "pitch", "yaw"]:
		var cfg: Dictionary = p.get(ax, {})
		for key in ["expo", "rate", "dz", "trim"]:
			(tx_axes[ax][key] as HSlider).set_value_no_signal(float(cfg.get(key, 0.0 if key != "rate" else 1.0)))
		(curve_views[ax] as CurveView).set_cfg(cfg)
	smooth_slider.set_value_no_signal(float(p.get("smoothing", 0.0)))

func _set_axis(ax: String, key: String, v: float) -> void:
	var p := _profile()
	if not p.has(ax):
		p[ax] = {"expo": 0.0, "rate": 1.0, "dz": 0.0, "trim": 0.0}
	p[ax][key] = v
	(curve_views[ax] as CurveView).set_cfg(p[ax])

func _on_profile_selected(i: int) -> void:
	var name := tx_profile_opt.get_item_text(i)
	var tx: Dictionary = Settings.data["transmitter"]
	if per_aircraft_chk.button_pressed:
		tx["per_aircraft"][aircraft_id] = name
	else:
		tx["active_profile"] = name
	_refresh_tx()

func _on_per_aircraft(on: bool) -> void:
	var tx: Dictionary = Settings.data["transmitter"]
	if on:
		tx["per_aircraft"][aircraft_id] = tx_profile_opt.get_item_text(tx_profile_opt.selected)
	else:
		(tx["per_aircraft"] as Dictionary).erase(aircraft_id)
	_refresh_tx()

func _save_as() -> void:
	var n := name_edit.text.strip_edges()
	if n == "":
		n = "Profile %d" % (Settings.data["transmitter"]["profiles"].size() + 1)
	var tx: Dictionary = Settings.data["transmitter"]
	tx["profiles"][n] = _profile().duplicate(true)
	if per_aircraft_chk.button_pressed:
		tx["per_aircraft"][aircraft_id] = n
	else:
		tx["active_profile"] = n
	name_edit.text = ""
	_refresh_tx()

func _delete_profile() -> void:
	var tx: Dictionary = Settings.data["transmitter"]
	var n := tx_profile_opt.get_item_text(tx_profile_opt.selected)
	if (tx["profiles"] as Dictionary).size() <= 1 or n in Settings.TX_PRESETS:
		return
	(tx["profiles"] as Dictionary).erase(n)
	if tx["active_profile"] == n:
		tx["active_profile"] = "Balanced"
	for k in (tx["per_aircraft"] as Dictionary).keys():
		if tx["per_aircraft"][k] == n:
			(tx["per_aircraft"] as Dictionary).erase(k)
	_refresh_tx()

func _apply_preset(pn: String) -> void:
	var src: Dictionary = Settings.TX_PRESETS[pn]
	var p := _profile()
	for k in src.keys():
		p[k] = (src[k].duplicate(true) if typeof(src[k]) == TYPE_DICTIONARY else src[k])
	_refresh_tx()

# ---------------------------------------------------------------- controls
func _tab_controls() -> void:
	var vb := _page("Controls")
	var mode := UITheme.option(["Mode 2 (throttle left)", "Mode 1 (throttle right)"], 0 if int(Settings.g("controls", "mode", 2)) == 2 else 1)
	mode.item_selected.connect(func(i): Settings.s("controls", "mode", 2 if i == 0 else 1))
	_row(vb, "Stick mode", mode)
	_row(vb, "Stick size", _slider(0.6, 1.6, 0.05, float(Settings.g("controls", "stick_size", 1.0)), func(v): Settings.s("controls", "stick_size", v)))
	_row(vb, "Stick opacity", _slider(0.15, 1.0, 0.05, float(Settings.g("controls", "opacity", 0.55)), func(v): Settings.s("controls", "opacity", v)))
	vb.add_child(_check("Larger flight telemetry", bool(Settings.g("controls", "large_telemetry", false)), func(on): Settings.s("controls", "large_telemetry", on)))
	vb.add_child(_check("Floating sticks (centre where you touch)", bool(Settings.g("controls", "floating", false)), func(on): Settings.s("controls", "floating", on)))
	vb.add_child(_check("Left-handed (swap sticks)", bool(Settings.g("controls", "left_handed", false)), func(on): Settings.s("controls", "left_handed", on)))
	vb.add_child(_check("Wheel brakes when throttle is at zero", bool(Settings.g("controls", "throttle_brake", true)), func(on): Settings.s("controls", "throttle_brake", on)))
	vb.add_child(UITheme.label("Bluetooth gamepads: right stick = aileron/elevator, left stick = rudder + throttle, triggers = throttle.", 17, UITheme.DIM))

# ---------------------------------------------------------------- graphics
func _tab_graphics() -> void:
	var vb := _page("Graphics")
	var qs := ["performance", "high", "ultra"]
	var q := UITheme.option(["Performance", "High", "Ultra"], qs.find(String(Settings.g("graphics", "quality", "high"))))
	q.item_selected.connect(func(i):
		Settings.s("graphics", "quality", qs[i])
		graphics_changed.emit())
	_row(vb, "Quality preset", q)
	_row(vb, "Render scale", _slider(0.5, 1.0, 0.05, float(Settings.g("graphics", "render_scale", 0.85)), func(v):
		Settings.s("graphics", "render_scale", v)
		graphics_changed.emit()))
	var fps := UITheme.option(["30 fps", "60 fps", "Unlimited"], [30, 60, 0].find(int(Settings.g("graphics", "fps", 60))))
	fps.item_selected.connect(func(i):
		Settings.s("graphics", "fps", [30, 60, 0][i])
		graphics_changed.emit())
	_row(vb, "Frame rate cap", fps)
	_row(vb, "Grass density (live)", _slider(0.0, 2.0, 0.1, float(Settings.g("graphics", "grass", 1.0)), func(v):
		Settings.s("graphics", "grass", v)
		graphics_changed.emit()))
	vb.add_child(_check("Automatic resolution scaling (keeps frame rate)", bool(Settings.g("graphics", "auto_scale", true)), func(on): Settings.s("graphics", "auto_scale", on)))
	vb.add_child(_check("Show performance overlay", bool(Settings.g("graphics", "show_fps", false)), func(on): Settings.s("graphics", "show_fps", on)))
	vb.add_child(UITheme.label("Flight physics always run at 120 Hz regardless of graphics quality.", 17, UITheme.DIM))

# ---------------------------------------------------------------- audio
func _tab_audio() -> void:
	var vb := _page("Audio")
	for d in [["master", "Master"], ["engine", "Engines"], ["effects", "Effects"], ["ambience", "Ambience"]]:
		var key: String = d[0]
		_row(vb, d[1], _slider(0.0, 1.0, 0.05, float(Settings.g("audio", key, 1.0)), func(v):
			Settings.s("audio", key, v)
			Sfx.apply_volumes()))

# ---------------------------------------------------------------- gameplay
func _tab_gameplay() -> void:
	var vb := _page("Gameplay")
	var assists := ["arcade", "sport", "expert"]
	var a := UITheme.option(["Arcade (self-levelling)", "Sport (rate damping)", "Expert / Full Real (no assists)"], assists.find(String(Settings.g("gameplay", "assist", "sport"))))
	a.item_selected.connect(func(i): Settings.s("gameplay", "assist", assists[i]))
	_row(vb, "Flight assistance", a)
	var dmg := ["off", "visual", "physical"]
	var d := UITheme.option(["Off (indestructible)", "Visual only", "Physical (full structural)"], dmg.find(String(Settings.g("gameplay", "damage", "physical"))))
	d.item_selected.connect(func(i): Settings.s("gameplay", "damage", dmg[i]))
	_row(vb, "Damage", d)
	vb.add_child(_check("Kill cam after serious crashes", bool(Settings.g("gameplay", "killcam", true)), func(on): Settings.s("gameplay", "killcam", on)))
	_row(vb, "Live aftermath (s)", _slider(1.0, 8.0, 0.5, float(Settings.g("gameplay", "aftermath", 4.0)), func(v): Settings.s("gameplay", "aftermath", v)))
	_row(vb, "Kill cam slow motion", _slider(0.1, 1.0, 0.05, float(Settings.g("gameplay", "slowmo", 0.3)), func(v): Settings.s("gameplay", "slowmo", v)))
	vb.add_child(_check("Landing feedback", bool(Settings.g("gameplay", "landing_feedback", true)), func(on): Settings.s("gameplay", "landing_feedback", on)))
	vb.add_child(_check("Pilot-view auto zoom", bool(Settings.g("gameplay", "auto_zoom", true)), func(on): Settings.s("gameplay", "auto_zoom", on)))
	var cams := CameraRig.MODES
	var c := UITheme.option(["Pilot (ground)", "Chase", "Locked chase", "Onboard", "Free orbit"], cams.find(String(Settings.g("gameplay", "camera", "pilot"))))
	c.item_selected.connect(func(i): Settings.s("gameplay", "camera", cams[i]))
	_row(vb, "Default camera", c)
	var u := UITheme.option(["Metric (km/h, m)", "Imperial (mph, ft)"], 0 if String(Settings.g("gameplay", "units", "metric")) == "metric" else 1)
	u.item_selected.connect(func(i): Settings.s("gameplay", "units", "metric" if i == 0 else "imperial"))
	_row(vb, "Units", u)

func _tab_about() -> void:
	var vb := _page("About")
	vb.add_child(UITheme.label("RC PARK  v%s" % Game.VERSION, 28))
	vb.add_child(UITheme.label("Godot %s  -  %s renderer  -  Jolt Physics" % [Engine.get_version_info().get("string", ""), RenderingServer.get_current_rendering_method()], 18, UITheme.DIM))
	vb.add_child(UITheme.label("All aircraft, liveries, the field, sounds and textures are generated procedurally by the game.\nNo third-party models, samples or brand assets are included.", 18, UITheme.DIM))
	var b := UITheme.button("EXPORT DIAGNOSTICS REPORT", 420)
	var lbl := UITheme.label("", 16, UITheme.DIM)
	b.pressed.connect(func():
		var p := Diag.export_report()
		lbl.text = "Saved in app storage: " + String(p.get("path", "")) if p.get("ok", false) else "Save failed: " + String(p.get("error", ""))
		if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
			DisplayServer.clipboard_set(String(p["text"]))
			lbl.text += "\nReport copied: paste into a message or document to share.")
	vb.add_child(b)
	vb.add_child(lbl)
	vb.add_child(UITheme.label("Diagnostics stay on this device. Nothing is uploaded.", 16, UITheme.DIM))
	var rs := UITheme.button("RESET ALL SETTINGS", 320)
	rs.pressed.connect(func():
		Settings.data = Settings.defaults()
		Settings.save()
		_refresh_tx())
	vb.add_child(rs)

func _close() -> void:
	if not Settings.save():
		var dialog := ConfirmationDialog.new()
		dialog.title = "Preferences not saved"
		dialog.dialog_text = Settings.last_save_error + "\nYour previous save was preserved."
		dialog.ok_button_text = "Close without saving"
		dialog.cancel_button_text = "Stay in settings"
		add_child(dialog)
		dialog.confirmed.connect(_finish_close)
		dialog.canceled.connect(dialog.queue_free)
		dialog.popup_centered(Vector2i(620, 220))
		return
	_finish_close()

func _finish_close() -> void:
	Sfx.apply_volumes()
	closed.emit()
	queue_free()

func _layout_safe() -> void:
	if not is_instance_valid(content_root): return
	var safe := UITheme.safe_area(self)
	content_root.offset_left = safe.position.x + 32
	content_root.offset_top = safe.position.y + 20
	content_root.offset_right = safe.end.x - size.x - 32
	content_root.offset_bottom = safe.end.y - size.y - 20
