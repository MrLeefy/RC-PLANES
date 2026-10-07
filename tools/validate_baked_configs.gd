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
	var worst_inertia := 0.0
	var tested := 0

	for item in _cases():
		var definition: Dictionary = item["definition"]
		var cfg: Dictionary = item["cfg"]
		var id := String(definition["id"])
		if not BakedLibrary.has_baked(id, 2):
			failures.append("%s missing baked resources" % id)
			continue

		var builder := AircraftBuilder.new()
		var legacy := builder.build(definition, cfg, 2)
		var baked_result := BakedLibrary.instantiate(definition, cfg, 2)
		if baked_result.is_empty():
			failures.append("%s baked instantiate failed" % id)
			(legacy["root"] as Node).free()
			continue
		var baked: Dictionary = baked_result["build"]
		tested += 1

		var md := absf(float(legacy["mass"]) - float(baked["mass"]))
		var cd := (legacy["cg"] as Vector3).distance_to(baked["cg"] as Vector3)
		worst_mass = maxf(worst_mass, md)
		worst_cg = maxf(worst_cg, cd)
		var li := _inertia(legacy)
		var bi := _inertia(baked)
		var inertia_error := 0.0
		for axis in 3:
			inertia_error = maxf(inertia_error, absf(li[axis] - bi[axis]) / maxf(li[axis], 0.0001))
		worst_inertia = maxf(worst_inertia, inertia_error)
		if inertia_error > 0.03:
			failures.append("%s inertia relative difference %.6f cfg=%s" % [id, inertia_error, cfg])
		if legacy["panels"] != baked["panels"]:
			failures.append("%s aerodynamic panel data differs" % id)

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

		print("%s mass_diff=%.6fkg cg_diff=%.6fm inertia_diff=%.6f mode=%s cfg=%s" % [
			id, md, cd, inertia_error, BakedLibrary.mode_for(definition, cfg, 2), cfg
		])
		(legacy["root"] as Node).free()
		(baked["root"] as Node).free()

	print("BAKED CONFIG VALIDATION cases=%d worst_mass=%.6fkg worst_cg=%.6fm worst_inertia=%.6f failures=%d" % [
		tested, worst_mass, worst_cg, worst_inertia, failures.size()
	])
	if not failures.is_empty():
		for f in failures:
			push_error(f)
		quit(2)
		return
	quit()

func _cases() -> Array:
	var cases := []
	for definition in AircraftDB.all():
		var base := {"battery": 0, "prop": 0, "cg": 0.0, "throws": "high", "fuel": 1.0, "engine": 0}
		var configs: Array = [base, _variant_cfg(definition)]
		for battery in (definition["batteries"] as Array).size():
			var cfg := base.duplicate()
			cfg["battery"] = battery
			if not configs.has(cfg): configs.append(cfg)
		for prop in (definition["props"] as Array).size():
			var cfg := base.duplicate()
			cfg["prop"] = prop
			if not configs.has(cfg): configs.append(cfg)
		for shift in [-0.06, 0.06]:
			var cfg := base.duplicate()
			cfg["cg"] = shift
			configs.append(cfg)
		var fuel := base.duplicate()
		fuel["fuel"] = 0.2
		configs.append(fuel)
		for cfg in configs:
			cases.append({"definition": definition, "cfg": cfg})
	return cases

func _inertia(build: Dictionary) -> Vector3:
	var result := Vector3.ZERO
	for comp in build["comps"]:
		for pm in comp["point_masses"]:
			var offset: Vector3 = (pm["pos"] as Vector3) - (build["cg"] as Vector3)
			var size: Vector3 = pm["size"]
			var mass := float(pm["m"])
			result.x += mass * (offset.y * offset.y + offset.z * offset.z + (size.y * size.y + size.z * size.z) / 12.0)
			result.y += mass * (offset.x * offset.x + offset.z * offset.z + (size.x * size.x + size.z * size.z) / 12.0)
			result.z += mass * (offset.x * offset.x + offset.y * offset.y + (size.x * size.x + size.y * size.y) / 12.0)
	return result
