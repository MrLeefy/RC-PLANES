extends Node
## Prints (or writes) the derived spec sheet of every aircraft.
##   godot --headless --path . res://tests/spec_dump.tscn -- [id] [--md docs/AIRCRAFT_SPECS_TABLE.md]
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var only := ""
	var md_path := ""
	var i := 0
	while i < args.size():
		if args[i] == "--md" and i + 1 < args.size():
			md_path = args[i + 1]
			i += 1
		else:
			only = args[i]
		i += 1
	var rows := []
	for d in AircraftDB.all():
		if only != "" and d["id"] != only:
			continue
		var t0 := Time.get_ticks_msec()
		var sp := AircraftSpecs.compute(d, {"battery": 0, "prop": 0, "cg": 0.0, "throws": "high", "fuel": 1.0})
		rows.append(sp)
		print(AircraftSpecs.summary(sp), "  CG %.0f%% ballast %.0f g slide %s [%d ms]" % [sp["cg_pct_mac"], float(sp["ballast_kg"]) * 1000.0, str((sp["cg_slide_range_pct"] as Array).map(func(x): return snappedf(x, 0.1))), Time.get_ticks_msec() - t0])
		if only != "":
			for k in sp.keys():
				print("   %-26s %s" % [k, str(sp[k])])
	if md_path != "":
		var f := FileAccess.open(md_path, FileAccess.WRITE)
		f.store_string(AircraftSpecs.markdown(rows))
		f.close()
	get_tree().quit()
