extends Node
## Dev tool: CPU timings for the boot stages and aircraft builds, headless (no GPU work).
## godot --headless --path . -- --test  with  RC_SUITE=res://tests/boot_timing.gd
## Prints "TIMING ..." lines, then quits. Numbers are build-container CPU time, not device time.

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var t0 := Time.get_ticks_msec()
	Game.wind = Wind.new()
	Game.wind.configure("light", "headwind", Vector3(1, 0, 0))
	var field := Field.new()
	field.name = "Field"
	field.time_preset = "golden"
	add_child(field)
	Game.field = field
	var tf := Time.get_ticks_msec()
	var last := [tf, ""]
	var on_progress := func(f: float, txt: String) -> void:
		var now := Time.get_ticks_msec()
		if txt != last[1]:
			if last[1] != "":
				print("TIMING   field phase %-28s %5d ms" % [last[1], now - last[0]])
			last[0] = now
			last[1] = txt
	await field.build_async("high", on_progress)
	print("TIMING field.build_async(high): %d ms" % (Time.get_ticks_msec() - tf))
	var ts := Time.get_ticks_msec()
	await Sfx.build_bank_async(func(_f, _t): pass)
	print("TIMING sfx.build_bank_async: %d ms" % (Time.get_ticks_msec() - ts))
	for id in ["skylark", "viper90", "skyliner", "macharrow", "belle51"]:
		var ta := Time.get_ticks_msec()
		var ac := Aircraft.new()
		ac.setup(AircraftDB.by_id(id), Settings.aircraft_cfg(id), 2, true)
		var tb := Time.get_ticks_msec() - ta
		add_child(ac)
		ac.queue_free()
		await get_tree().process_frame
		print("TIMING aircraft setup %-10s lod2: %d ms" % [id, tb])
	var tb0 := Time.get_ticks_msec()
	AircraftBuilder.new().build(AircraftDB.by_id("viper90"), {}, 1)
	print("TIMING builder.build only viper90 detail1: %d ms" % (Time.get_ticks_msec() - tb0))
	var tm := Time.get_ticks_msec()
	var a := Aircraft.new()
	a.setup(AircraftDB.by_id("viper90"), {}, 1, true)
	add_child(a)
	var tsetup := Time.get_ticks_msec() - tm
	var tm2 := Time.get_ticks_msec()
	field._merge_static_visual(a)
	print("TIMING parked viper90 detail1: setup %d ms, merge %d ms" % [tsetup, Time.get_ticks_msec() - tm2])
	print("TIMING total: %d ms" % (Time.get_ticks_msec() - t0))
	get_tree().quit()
