extends SceneTree
## Validates the data-only Workshop configurator against the legacy procedural
## builder. Geometry is intentionally static; flight-relevant mass/CG/prop data
## must remain equivalent within tight tolerances.

const BakedLibrary = preload("res://scripts/aircraft/aircraft_baked_library.gd")

func _initialize() -> void:
	call_deferred("_run")

func _variant_cfg(definition: Dictionary) -> Dictionary:
	var batteries: Array = definition["batteries"]
	var props: Array = definition["props"]
	return {
		"battery": mini(1, maxi(batteries.size() - 1, 0)),
		"prop": mini(1, maxi(props.size() - 1, 0)),
		"cg": 0.03,
		"throws": "low",
		"fuel": 0.55,
		"engine": 0,
	}

func _run() -> void:
	var failures := []
	var worst_mass := 0.0
	var worst_cg := 0.0

	for definition in AircraftDB.all():
		var id := String(definition["id"])
		if not BakedLibrary.has_baked(id, 2):
			failures.append("%s missing baked resources" % id)
			continue
		var cfg := _variant_cfg(definition)

		var builder := AircraftBuilder.new()
		var legacy := builder.build(definition, cfg, 2)
		var baked_result := BakedLibrary.instantiate(definition, cfg, 2)
		if baked_result.is_empty():
			failures.append("%s baked instantiate failed" % id)
			(legacy["root"] as Node).free()
			continue
		var baked: Dictionary = baked_result["build"]

		var md := absf(float(legacy["mass"]) - float(baked["mass"]))
		var cd := (legacy["cg"] as Vector3).distance_to(baked["cg"] as Vector3)
		worst_mass = maxf(worst_mass, md)
		worst_cg = maxf(worst_cg, cd)

		var counts_ok := (
			(legacy["comps"] as Array).size() == (baked["comps"] as Array).size()
			and (legacy["panels"] as Array).size() == (baked["panels"] as Array).size()
			and (legacy["surfaces"] as Array).size() == (baked["surfaces"] as Array).size()
			and (legacy["engines"] as Array).size() == (baked["engines"] as Array).size()
			and (legacy["wheels"] as Array).size() == (baked["wheels"] as Array).size()
		)
		if not counts_ok:
			failures.append("%s structural counts differ" % id)

		# Gear location is now static by design when CG is changed in Workshop,
		# so CG may differ by a few millimetres from the legacy behavior that
		# physically moved gear with the battery/CG slider.
		if md > 0.002:
			failures.append("%s mass diff %.6f kg" % [id, md])
		if cd > 0.015:
			failures.append("%s CG diff %.6f m" % [id, cd])

		var le: Array = legacy["engines"]
		var be: Array = baked["engines"]
		for i in mini(le.size(), be.size()):
			if absf(float(le[i]["D"]) - float(be[i]["D"])) > 0.00001:
				failures.append("%s engine%d prop diameter differs" % [id, i])
			if absf(float(le[i]["pitch"]) - float(be[i]["pitch"])) > 0.00001:
				failures.append("%s engine%d prop pitch differs" % [id, i])
			if int(le[i]["blades"]) != int(be[i]["blades"]):
				failures.append("%s engine%d blade count differs" % [id, i])

		var wheel_load := 0.0
		for w in baked["wheels"]:
			wheel_load += float(w.get("load", 0.0))
		if not (wheel_load > float(baked["mass"]) * 9.81 * 0.95 and wheel_load < float(baked["mass"]) * 9.81 * 1.15):
			failures.append("%s baked gear load %.3f N inconsistent with mass %.3f kg" % [id, wheel_load, baked["mass"]])

		print("%s mass_diff=%.6fkg cg_diff=%.6fm mode=%s" % [
			id, md, cd, BakedLibrary.mode_for(definition, cfg, 2)
		])
		(legacy["root"] as Node).free()
		(baked["root"] as Node).free()

	print("BAKED CONFIG VALIDATION worst_mass=%.6fkg worst_cg=%.6fm failures=%d" % [
		worst_mass, worst_cg, failures.size()
	])
	if not failures.is_empty():
		for f in failures:
			push_error(f)
		quit(2)
		return
	quit()
