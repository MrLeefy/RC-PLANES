extends Node
## Boot: loading screen -> build field + sound bank + FX pools -> hangar <-> flight.
## Also owns graphics scaling (quality presets + automatic resolution scaling).

var world: Node3D
var field: Field
var fx: Fx
var cam: CameraRig
var ui: CanvasLayer
var loading: Control
var load_bar: ProgressBar
var load_label: Label
var menu: HangarMenu
var settings_ui: SettingsUI
var flight: Flight
var display_ac: Aircraft
var state := "loading"
var _scale := 0.85
var _auto_t := 0.0
var _frame_acc := 0.0
var _frame_n := 0
var scaler := AdaptiveScale.new()
var phys_gov := PhysicsGovernor.new()

func _ready() -> void:
	get_tree().set_quit_on_go_back(false)
	process_mode = Node.PROCESS_MODE_ALWAYS
	world = Node3D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.name = "World"
	add_child(world)
	ui = CanvasLayer.new()
	ui.process_mode = Node.PROCESS_MODE_PAUSABLE
	ui.layer = 10
	add_child(ui)
	cam = CameraRig.new()
	world.add_child(cam)
	_apply_graphics()
	if "--test" in OS.get_cmdline_user_args() or "--upgrade-test" in OS.get_cmdline_user_args():
		var suite := OS.get_environment("RC_SUITE") if OS.get_environment("RC_SUITE") != "" else "res://tests/realism_tests.gd" if "--upgrade-test" in OS.get_cmdline_user_args() else "res://tests/test_runner.gd"
		var t = load(suite).new()
		add_child(t)
		return
	_build_loading()
	await get_tree().process_frame
	await _boot()

func _build_loading() -> void:
	loading = Control.new()
	loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading.theme = UITheme.theme()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.08)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loading.add_child(bg)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 16)
	var t := UITheme.label("RC PARK", 72)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var s := UITheme.label("REALISM  -  FUN  -  NO LIMITS", 20, UITheme.ACCENT)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(s)
	load_bar = ProgressBar.new()
	load_bar.custom_minimum_size = Vector2(620, 14)
	load_bar.show_percentage = false
	load_bar.add_theme_stylebox_override("background", UITheme.sb(Color(1, 1, 1, 0.1), 7, 0, Color(0, 0, 0, 0), 0))
	load_bar.add_theme_stylebox_override("fill", UITheme.sb(UITheme.ACCENT, 7, 0, Color(0, 0, 0, 0), 0))
	vb.add_child(load_bar)
	load_label = UITheme.label("Loading", 20, UITheme.DIM)
	load_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(load_label)
	var tip := UITheme.label("Tip: rewind 5 s to retry a landing - or crash it and enjoy the kill cam.", 17, UITheme.DIM)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tip)
	loading.add_child(vb)
	ui.add_child(loading)
	await get_tree().process_frame
	vb.position = (loading.size - vb.size) * 0.5

func _progress(f: float, txt: String) -> void:
	if load_bar:
		load_bar.value = f * 100.0
		load_label.text = txt

func _boot() -> void:
	Game.wind = Wind.new()
	Game.wind.configure(String(Settings.g("environment", "wind", "light")), String(Settings.g("environment", "wind_dir", "headwind")), Vector3(1, 0, 0))
	field = Field.new()
	field.name = "Field"
	field.time_preset = String(Settings.g("environment", "time", "golden"))
	world.add_child(field)
	Game.field = field
	await field.build_async(String(Settings.g("graphics", "quality", "high")), func(f, t): _progress(f * 0.85, t))
	await Sfx.build_bank_async(func(f, t): _progress(0.85 + f * 0.1, t))
	fx = Fx.new()
	fx.name = "Fx"
	world.add_child(fx)
	fx.setup()
	Game.fx = fx
	_apply_graphics()
	# pre-warm crash effects and materials while the loading screen is still up
	_progress(0.97, "Warming up")
	cam.global_position = Vector3(0, 2, 10)
	fx.prewarm(cam.global_position)
	await get_tree().process_frame
	await get_tree().process_frame
	fx.end_prewarm()
	_progress(1.0, "Ready")
	_open_menu()
	var tw := create_tween()
	tw.tween_property(loading, "modulate:a", 0.0, 0.5)
	tw.tween_callback(loading.queue_free)
	Sfx.start_ambience()

# ================================================================ graphics
func _apply_graphics() -> void:
	var q := String(Settings.g("graphics", "quality", "high"))
	var vp := get_viewport()
	scaler.configure(float(Settings.g("graphics", "render_scale", 0.85)), int(Settings.g("graphics", "fps", 60)), q == "ultra")
	phys_gov.configure(int(Settings.g("graphics", "fps", 60)))
	_scale = scaler.scale
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = _scale
	vp.msaa_3d = Viewport.MSAA_DISABLED if q == "performance" else (Viewport.MSAA_4X if q == "ultra" else Viewport.MSAA_2X)
	vp.mesh_lod_threshold = 2.0 if q == "performance" else (1.0 if q == "high" else 0.6)
	Engine.max_fps = int(Settings.g("graphics", "fps", 60))
	if field:
		field.apply_quality(q)

func _process(delta: float) -> void:
	_govern_physics(delta)
	if not bool(Settings.g("graphics", "auto_scale", true)) or state == "loading" or get_tree().paused:
		return
	if scaler.update(delta, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)):
		_scale = scaler.scale
		get_viewport().scaling_3d_scale = _scale
		Diag.log_event("Render scale %.3f: %s" % [_scale, scaler.reason])

## Drops the physics tick rate only while the plane is high in the air and the CPU is the limit; see
## PhysicsGovernor. Anything near the ground, crashed, paused or in a replay runs at the full 120 Hz.
func _govern_physics(delta: float) -> void:
	var want := PhysicsGovernor.FULL_HZ
	if bool(Settings.g("graphics", "adaptive_physics", true)) and state == "flight" and is_instance_valid(flight) \
			and flight.state == Flight.S.FLYING and not get_tree().paused and is_instance_valid(flight.aircraft):
		var a: Aircraft = flight.aircraft
		var agl := minf(a.agl, a.terrain_agl) if a.altitude_valid else a.agl
		var ticks := float(Engine.physics_ticks_per_second) * delta
		var cpu := Performance.get_monitor(Performance.TIME_PROCESS) + Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * ticks
		want = phys_gov.update(delta, cpu, agl, a.on_ground or a.crashed_flag)
	else:
		phys_gov.update(delta, 0.0, 0.0, true)
	if want != Engine.physics_ticks_per_second:
		Engine.physics_ticks_per_second = want
		Diag.log_event("Physics %d Hz: %s" % [want, phys_gov.reason])

# ================================================================ hangar
func _open_menu() -> void:
	state = "menu"
	field.set_time_of_day(String(Settings.g("environment", "time", "golden")))
	Game.wind.configure(String(Settings.g("environment", "wind", "light")), String(Settings.g("environment", "wind_dir", "headwind")), Vector3(1, 0, 0))
	menu = HangarMenu.new()
	ui.add_child(menu)
	menu.fly.connect(_start_flight)
	menu.open_settings.connect(_open_settings)
	menu.aircraft_changed.connect(_show_display)
	menu.config_changed.connect(_on_config_changed)
	menu.orbit.connect(func(rel): cam.orbit_drag(rel))
	menu.zoom.connect(func(f): cam.orbit_zoom(f))
	menu.env_changed.connect(func():
		field.set_time_of_day(String(Settings.g("environment", "time", "golden")))
		Game.wind.configure(String(Settings.g("environment", "wind", "light")), String(Settings.g("environment", "wind_dir", "headwind")), Vector3(1, 0, 0)))
	_show_display(menu.sel_id)

## Hangar display aircraft are expensive to build (~1 s of CPU each), so the last few stay built, hidden and
## idle. The carousel neighbours are built while the player is idle, so swiping does not stall the frame.
const DISPLAY_CACHE_MAX := 4
var _display_cache: Dictionary = {}   # id -> Aircraft (hidden unless it is the shown display)
var _display_lru: Array = []          # ids, least recently shown first
var _prebuild_pending := false

func _display_for(id: String) -> Aircraft:
	if _display_cache.has(id) and is_instance_valid(_display_cache[id]):
		_display_lru.erase(id)
		_display_lru.append(id)
		return _display_cache[id]
	var ac := Aircraft.new()
	ac.setup(AircraftDB.by_id(id), Settings.aircraft_cfg(id), 2, true)
	ac.visible = false
	ac.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(ac)
	_display_cache[id] = ac
	_display_lru.append(id)
	while _display_lru.size() > DISPLAY_CACHE_MAX:
		var victim := ""
		for k in _display_lru:
			if _display_cache.get(k) != display_ac:
				victim = String(k)
				break
		if victim == "":
			break
		_drop_display(victim)
	return ac

func _drop_display(id: String) -> void:
	_display_lru.erase(id)
	if _display_cache.has(id):
		var ac = _display_cache[id]
		_display_cache.erase(id)
		if is_instance_valid(ac):
			if ac == display_ac:
				display_ac = null
			ac.queue_free()

func _clear_display_cache() -> void:
	for id in _display_cache.keys():
		_drop_display(String(id))
	display_ac = null

func _on_config_changed(id: String) -> void:
	_drop_display(id)
	_show_display(id)

## At most one prebuild is pending, so rapid swiping cannot queue several one-second builds.
func _schedule_prebuild(delay := 0.3) -> void:
	if _prebuild_pending:
		return
	_prebuild_pending = true
	get_tree().create_timer(delay).timeout.connect(_prebuild_neighbours)

func _prebuild_neighbours() -> void:
	_prebuild_pending = false
	if state != "menu" or menu == null or not is_instance_valid(menu):
		return
	var ids := AircraftDB.ids()
	var i := ids.find(menu.sel_id)
	for j in [i + 1, i - 1]:
		if j >= 0 and j < ids.size() and not _display_cache.has(ids[j]):
			_display_for(ids[j])
			_schedule_prebuild(0.15)
			return

func _show_display(id: String) -> void:
	if display_ac and is_instance_valid(display_ac):
		display_ac.visible = false
		display_ac.process_mode = Node.PROCESS_MODE_DISABLED
	display_ac = _display_for(id)
	display_ac.visible = true
	display_ac.process_mode = Node.PROCESS_MODE_INHERIT
	_schedule_prebuild()
	var low := 0.0
	for w in display_ac.wheels:
		low = minf(low, (w["center"] as Vector3).y - float(w["r"]))
	var b := Basis(Vector3.UP, deg_to_rad(-58.0))
	display_ac.global_transform = Transform3D(b, Vector3(0, 0.05 - low, 3.0))
	display_ac.gear_pos = 1.0
	cam.target = display_ac
	cam.override_target = false
	cam.set_mode("free")
	var sz := maxf(display_ac.span, display_ac.length_m)
	cam.orbit_dist = clampf(sz * 1.35, 1.6, 7.5)
	cam.orbit_yaw = deg_to_rad(150.0)
	cam.orbit_pitch = 0.13
	cam.hangar_offset = sz * 0.28
	cam.snap()

func _process_menu_idle(delta: float) -> void:
	pass

func _open_settings() -> void:
	if settings_ui and is_instance_valid(settings_ui):
		return
	settings_ui = SettingsUI.new()
	settings_ui.aircraft_id = menu.sel_id if menu and is_instance_valid(menu) else (String(flight.aircraft.def["id"]) if flight else "skylark")
	ui.add_child(settings_ui)
	settings_ui.graphics_changed.connect(_apply_graphics)
	settings_ui.closed.connect(func():
		_apply_graphics()
		if menu and is_instance_valid(menu):
			menu._refresh_info())

# ================================================================ flight
func _start_flight() -> void:
	cam.hangar_offset = 0.0
	var id := menu.sel_id
	var mode_id := String(Settings.data.get("last_mode", "free"))
	menu.queue_free()
	menu = null
	_clear_display_cache()
	field.set_time_of_day(String(Settings.g("environment", "time", "golden")))
	flight = Flight.new()
	flight.name = "Flight"
	world.add_child(flight)
	flight.exit_to_hangar.connect(_end_flight)
	flight.open_settings.connect(_open_settings)
	flight.start(id, mode_id, field, fx, cam, ui)
	state = "flight"

func _end_flight() -> void:
	get_tree().paused = false
	if flight:
		flight.stop()
		flight = null
	fx.clear_chips()
	field.reset_npcs()
	_open_menu()

func _handle_back() -> void:
	# One navigation owner. Closing Settings must never resume paused flight.
	if UITheme.close_top_popup(ui): return
	if is_instance_valid(settings_ui) and not settings_ui.is_queued_for_deletion():
		settings_ui._close()
	elif is_instance_valid(flight):
		flight.handle_back()
	elif is_instance_valid(menu):
		menu.close_panels()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_handle_back()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back()
	elif what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED]:
		scaler.reset_window()
