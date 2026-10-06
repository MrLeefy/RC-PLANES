class_name HangarMenu
extends Control
## Aircraft selection / configuration screen over the live 3D field.

signal fly
signal open_settings
signal aircraft_changed(id: String)
signal config_changed(id: String)
signal orbit(rel: Vector2)
signal zoom(f: float)
signal env_changed

var sel_id := "skylark"
var name_l: Label
var cat_l: Label
var blurb_l: Label
var stats_l: Label
var ws_box: VBoxContainer
var cards: Dictionary = {}
var carousel: HBoxContainer
var right: PanelContainer
var top: HBoxContainer
var fly_btn: Button
var setup_box: HBoxContainer
var setup_panel: PanelContainer
var setup_btn: Button
var workshop_btn: Button
var info_scroll: ScrollContainer
var gesture: OrbitGesture
var orbit_hint: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	sel_id = String(Settings.data.get("last_aircraft", "skylark"))
	if not sel_id in AircraftDB.ids():
		sel_id = "skylark"
	gesture = OrbitGesture.new()
	gesture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	gesture.orbit.connect(func(relative): orbit.emit(relative))
	gesture.zoom.connect(func(factor): zoom.emit(factor))
	add_child(gesture)
	setup_panel = PanelContainer.new()
	setup_panel.visible = false
	setup_box = HBoxContainer.new()
	setup_box.add_theme_constant_override("separation", 16)
	setup_panel.add_child(setup_box)
	# ---- top bar
	top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	var logo := VBoxContainer.new()
	logo.add_theme_constant_override("separation", -8)
	var l1 := UITheme.label("RC PARK", 36, Color.WHITE)
	l1.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l1.add_theme_constant_override("shadow_offset_y", 2)
	logo.add_child(l1)
	var l2 := UITheme.label("REALISM  -  FUN  -  NO LIMITS", 13, UITheme.ACCENT)
	logo.add_child(l2)
	top.add_child(logo)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(16, 0)
	top.add_child(sp)
	var mode_ids := []
	var mode_names := []
	for m in Modes.LIST:
		mode_ids.append(m[0])
		mode_names.append(m[1])
	_top_opt("Mode", mode_names, mode_ids.find(String(Settings.data.get("last_mode", "free"))), func(i): Settings.data["last_mode"] = mode_ids[i])
	var times := ["morning", "midday", "golden", "overcast"]
	_top_opt("Time", ["Morning", "Midday", "Golden hour", "Overcast"], times.find(String(Settings.g("environment", "time", "golden"))), func(i):
		Settings.s("environment", "time", times[i])
		env_changed.emit())
	var winds := ["calm", "light", "moderate", "strong", "gusty"]
	_top_opt("Wind", ["Calm", "Light", "Moderate", "Strong", "Gusty"], winds.find(String(Settings.g("environment", "wind", "light"))), func(i):
		Settings.s("environment", "wind", winds[i])
		env_changed.emit())
	var dirs := ["headwind", "crosswind_left", "crosswind_right", "quartering", "tailwind"]
	_top_opt("From", ["Headwind", "Cross (left)", "Cross (right)", "Quartering", "Tailwind"], dirs.find(String(Settings.g("environment", "wind_dir", "headwind"))), func(i):
		Settings.s("environment", "wind_dir", dirs[i])
		env_changed.emit())
	var assists := ["arcade", "sport", "expert"]
	_top_opt("Assist", ["Arcade", "Sport", "Expert"], assists.find(String(Settings.g("gameplay", "assist", "sport"))), func(i): Settings.s("gameplay", "assist", assists[i]))
	var dmg := ["off", "visual", "physical"]
	_top_opt("Damage", ["Off", "Visual", "Physical"], dmg.find(String(Settings.g("gameplay", "damage", "physical"))), func(i): Settings.s("gameplay", "damage", dmg[i]))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(fill)
	setup_btn = UITheme.button("FLIGHT SETUP", 185, 20)
	setup_btn.pressed.connect(func():
		setup_panel.visible = not setup_panel.visible
		setup_btn.text = "CLOSE SETUP" if setup_panel.visible else "FLIGHT SETUP"
		_layout())
	top.add_child(setup_btn)
	var sb := UITheme.button("SETTINGS", 150, 20)
	sb.pressed.connect(func(): open_settings.emit())
	top.add_child(sb)
	add_child(top)
	# ---- right info panel
	right = PanelContainer.new()
	info_scroll = ScrollContainer.new()
	info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(info_scroll)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 9)
	info_scroll.add_child(vb)
	name_l = UITheme.label("", 32)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(name_l)
	cat_l = UITheme.label("", 19, UITheme.ACCENT)
	cat_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(cat_l)
	blurb_l = UITheme.label("", 17, UITheme.DIM)
	blurb_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb_l.custom_minimum_size = Vector2(330, 0)
	vb.add_child(blurb_l)
	stats_l = UITheme.label("", 19)
	stats_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(stats_l)
	workshop_btn = UITheme.button("OPEN WORKSHOP", 0, 21)
	workshop_btn.pressed.connect(func():
		ws_box.visible = not ws_box.visible
		workshop_btn.text = "CLOSE WORKSHOP" if ws_box.visible else "OPEN WORKSHOP"
		_layout())
	vb.add_child(workshop_btn)
	ws_box = VBoxContainer.new()
	ws_box.visible = false
	ws_box.add_theme_constant_override("separation", 10)
	vb.add_child(ws_box)
	add_child(right)
	add_child(setup_panel)
	orbit_hint = UITheme.label("Drag to inspect  ·  Pinch to zoom", 21, UITheme.TEXT)
	orbit_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	orbit_hint.add_theme_color_override("font_shadow_color", Color(0,0,0,0.8))
	orbit_hint.add_theme_constant_override("shadow_offset_y", 2)
	add_child(orbit_hint)
	# ---- carousel
	var sc := ScrollContainer.new()
	sc.name = "Carousel"
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	carousel = HBoxContainer.new()
	carousel.add_theme_constant_override("separation", 10)
	sc.add_child(carousel)
	for d in AircraftDB.all():
		var b := Button.new()
		b.custom_minimum_size = Vector2(196, 84)
		b.text = "%s\n%s" % [d["name"], d["category"]]
		b.add_theme_font_size_override("font_size", 17)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		# Cards never take the pointer themselves: a drag that happens to end over a card must scroll the strip,
		# not select that card. Taps are resolved in _carousel_input() instead.
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var id: String = d["id"]
		carousel.add_child(b)
		cards[id] = b
	sc.gui_input.connect(_carousel_input.bind(sc))
	add_child(sc)
	fly_btn = UITheme.accent_button("FLY  >", 260, 34)
	fly_btn.custom_minimum_size = Vector2(260, 78)
	fly_btn.pressed.connect(func():
		Settings.data["last_aircraft"] = sel_id
		Settings.save()
		fly.emit())
	add_child(fly_btn)
	resized.connect(_layout)
	_layout()
	select(sel_id, true)

var _tap_start := Vector2.ZERO
var _tap_time := 0
var _tap_moved := false
var _tap_down := false
const TAP_SLOP := 18.0

## Tap selects a card; a drag scrolls the strip and selects nothing (touch and mouse).
func _carousel_input(ev: InputEvent, sc: ScrollContainer) -> void:
	var pos := Vector2.ZERO
	var kind := ""
	if ev is InputEventScreenTouch and (ev as InputEventScreenTouch).index == 0:
		pos = (ev as InputEventScreenTouch).position
		kind = "down" if (ev as InputEventScreenTouch).pressed else "up"
	elif ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and ev.device != InputEvent.DEVICE_ID_EMULATION:
		pos = (ev as InputEventMouseButton).position
		kind = "down" if (ev as InputEventMouseButton).pressed else "up"
	elif ev is InputEventScreenDrag and (ev as InputEventScreenDrag).index == 0:
		if _tap_down and (ev as InputEventScreenDrag).position.distance_to(_tap_start) > TAP_SLOP:
			_tap_moved = true
		return
	elif ev is InputEventMouseMotion and ev.device != InputEvent.DEVICE_ID_EMULATION and _tap_down:
		var mm := ev as InputEventMouseMotion
		if mm.position.distance_to(_tap_start) > TAP_SLOP:
			_tap_moved = true
		if _tap_moved:
			sc.scroll_horizontal -= int(mm.relative.x)   # desktop mouse drag-scroll (touch is handled by the container)
		return
	else:
		return
	if kind == "down":
		_tap_down = true
		_tap_moved = false
		_tap_start = pos
		_tap_time = Time.get_ticks_msec()
	elif _tap_down:
		_tap_down = false
		if not _tap_moved and Time.get_ticks_msec() - _tap_time < 700 and pos.distance_to(_tap_start) <= TAP_SLOP:
			var g := sc.get_global_rect().position + pos
			for k in cards.keys():
				if (cards[k] as Control).get_global_rect().has_point(g):
					select(String(k))
					break

func _top_opt(label_text: String, items: Array, sel: int, cb: Callable) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.add_child(UITheme.label(label_text.to_upper(), 12, UITheme.DIM))
	var o := UITheme.option(items, maxi(sel, 0))
	o.custom_minimum_size = Vector2(155, 58)
	o.add_theme_font_size_override("font_size", 20)
	o.item_selected.connect(cb)
	box.add_child(o)
	if label_text in ["From", "Assist", "Damage"]:
		setup_box.add_child(box)
	else:
		top.add_child(box)

func _layout() -> void:
	if not is_instance_valid(fly_btn): return
	var sa := UITheme.safe_area(self)
	top.position = sa.position + Vector2(24, 12)
	top.size = Vector2(sa.size.x - 48, 78)
	var sc: ScrollContainer = get_node("Carousel")
	sc.position = Vector2(sa.position.x + 24, sa.end.y - 108)
	sc.size = Vector2(sa.size.x - 48, 96)
	var width := clampf(sa.size.x * 0.31, 380, 480)
	right.position = Vector2(sa.end.x - 24 - width, sa.position.y + 108)
	right.size = Vector2(width, maxf(150.0, sa.size.y - 325.0))
	info_scroll.custom_minimum_size = Vector2(0, 0)
	fly_btn.size = Vector2(width, 78)
	fly_btn.position = Vector2(right.position.x, sa.end.y - 204)
	setup_panel.reset_size()
	setup_panel.position = Vector2(sa.position.x + 24, sa.position.y + 108)
	orbit_hint.position = Vector2(sa.position.x + 30, sa.end.y - 155)

func select(id: String, force := false) -> void:
	if id == sel_id and not force:
		return
	sel_id = id
	for k in cards.keys():
		(cards[k] as Button).set_pressed_no_signal(k == id)
	_refresh_info()
	aircraft_changed.emit(id)

func _refresh_info() -> void:
	var d := AircraftDB.by_id(sel_id)
	var cfg := Settings.aircraft_cfg(sel_id)
	name_l.text = String(d["name"])
	cat_l.text = "%s  -  %s construction" % [d["category"], String(d["material"]).replace("film", "balsa/film").replace("painted", "painted composite").replace("metal", "scale metal finish")]
	blurb_l.text = String(d["blurb"])
	var e0: Dictionary = d["engines"][0]
	var span := 0.0
	var area := 0.0
	for w in d["wings"]:
		span = maxf(span, float(w["span"]))
		area += float(w["span"]) * 0.5 * (float(w["root"]) + float(w["tip"]))
	var power := ""
	var payload := 0.0
	match String(e0["type"]):
		"electric", "edf":
			var bats: Array = d["batteries"]
			var b: Dictionary = bats[clampi(int(cfg["battery"]), 0, bats.size() - 1)] if bats.size() > 0 else {"name": "6S", "mass": 0.7}
			payload = float(b["mass"])
			power = "Electric prop  -  " + String(b["name"])
			if String(e0["type"]) == "edf":
				power = "%.0f mm EDF x%d  -  %s" % [float(e0["fan_d"]) * 1000.0, d["engines"].size(), b["name"]]
			elif d["engines"].size() > 1:
				power = "Electric x%d  -  %s" % [d["engines"].size(), b["name"]]
		"glow2": power = "Glow 2-stroke"
		"glow4": power = "Glow 4-stroke"
		"gas2": power = "Gasoline 2-stroke"
		"turbine": power = "Kerosene turbine %.0f N" % float(e0["thrust"])
	if not String(e0["type"]) in ["electric", "edf"]:
		payload = float(d["tank"]) * 0.8 * float(cfg["fuel"])
		power += "  -  %.0f ml tank" % (float(d["tank"]) * 1000.0)
	var auw := float(d["mass"]) + payload
	var props: Array = d["props"]
	var prop_txt := ""
	if props.size() > 0:
		prop_txt = "Prop  " + String(props[clampi(int(cfg["prop"]), 0, props.size() - 1)]["name"])
	stats_l.text = "Span %.2f m   Length %.2f m\nWeight %.2f kg   Wing loading %.1f kg/m2\n%s\n%s   Tx: %s" % [span, float(d["length"]), auw, auw / maxf(area, 0.01), power, prop_txt, Settings.tx_profile_name_for(sel_id)]
	_build_workshop(d, cfg)

func _build_workshop(d: Dictionary, cfg: Dictionary) -> void:
	for c in ws_box.get_children():
		c.queue_free()
	var bats: Array = d["batteries"]
	if bats.size() > 0:
		var names := []
		for b in bats:
			names.append(b["name"])
		_ws_opt("Battery", names, int(cfg["battery"]), func(i): _cfg_set("battery", i))
	var props: Array = d["props"]
	if props.size() > 0:
		var pn := []
		for p in props:
			pn.append(p["name"])
		_ws_opt("Propeller", pn, int(cfg["prop"]), func(i): _cfg_set("prop", i))
	if float(d["tank"]) > 0.0:
		_ws_slider("Fuel load", 0.2, 1.0, float(cfg["fuel"]), func(v): _cfg_set("fuel", v))
	_ws_slider("CG shift (%% MAC)", -0.06, 0.06, float(cfg["cg"]), func(v): _cfg_set("cg", v))
	_ws_opt("Control throws", ["High rates", "Low rates"], 0 if String(cfg["throws"]) == "high" else 1, func(i): _cfg_set("throws", "high" if i == 0 else "low"))

func _ws_opt(label_text: String, items: Array, sel: int, cb: Callable) -> void:
	var hb := HBoxContainer.new()
	var l := UITheme.label(label_text, 16, UITheme.DIM)
	l.custom_minimum_size = Vector2(122, 0)
	hb.add_child(l)
	var o := UITheme.option(items, sel)
	o.custom_minimum_size = Vector2(205, 56)
	o.add_theme_font_size_override("font_size", 19)
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	o.item_selected.connect(cb)
	hb.add_child(o)
	ws_box.add_child(hb)

func _ws_slider(label_text: String, a: float, b: float, v: float, cb: Callable) -> void:
	var hb := HBoxContainer.new()
	var l := UITheme.label(label_text.replace("%%", "%"), 16, UITheme.DIM)
	l.custom_minimum_size = Vector2(122, 0)
	hb.add_child(l)
	var s := HSlider.new()
	s.min_value = a
	s.max_value = b
	s.step = 0.005
	s.value = v
	s.custom_minimum_size = Vector2(205, 52)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.drag_ended.connect(func(_c): cb.call(s.value))
	hb.add_child(s)
	ws_box.add_child(hb)

func _cfg_set(key: String, v) -> void:
	var cfg := Settings.aircraft_cfg(sel_id)
	cfg[key] = v
	Settings.save()
	_refresh_info()
	config_changed.emit(sel_id)

func close_panels() -> void:
	if setup_panel.visible:
		setup_panel.visible = false
		setup_btn.text = "FLIGHT SETUP"
	elif is_instance_valid(ws_box):
		ws_box.visible = false
		workshop_btn.text = "OPEN WORKSHOP"
	gesture.release_all()
	_layout()
