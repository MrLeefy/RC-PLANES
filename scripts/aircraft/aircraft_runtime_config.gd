class_name AircraftRuntimeConfig
extends RefCounted
## Applies Workshop configuration to an offline-baked aircraft blueprint without
## regenerating any render geometry.

static func apply(build: Dictionary, definition: Dictionary, cfg: Dictionary) -> void:
	var comps: Array = build["comps"]
	var core_index := 0
	for i in comps.size():
		if String(comps[i].get("id", "")) == "fuselage":
			core_index = i
			break

	# Remove configuration-dependent masses captured by the default offline bake.
	# Static structure + engine point masses remain unchanged.
	for c in comps:
		var keep := []
		for pm in c.get("point_masses", []):
			if bool(pm.get("payload", false)) or bool(pm.get("radio", false)) or bool(pm.get("ballast", false)):
				continue
			keep.append((pm as Dictionary).duplicate(true))
		c["point_masses"] = keep
		var cm := 0.0
		for pm in keep:
			cm += float(pm["m"])
		c["mass"] = cm

	var length := float(build["length"])
	var mac: Dictionary = build["mac"]
	var c_mac := float(mac["c"])
	var zle := float(mac["zle"])
	var z_target := zle + (float(definition["cg"]) + float(cfg.get("cg", 0.0))) * c_mac
	var etype := String(definition["engines"][0]["type"])

	# Prop selection changes propulsion physics, not the static airframe mesh.
	var props: Array = definition["props"]
	if not props.is_empty():
		var pi := clampi(int(cfg.get("prop", 0)), 0, props.size() - 1)
		var prop: Dictionary = props[pi]
		for engine in build["engines"]:
			if String(engine["type"]) in ["electric", "glow2", "glow4", "gas2"]:
				engine["D"] = float(prop["d"])
				engine["pitch"] = float(prop["pitch"])
				engine["blades"] = int(prop["blades"])
				var pci := int(engine.get("prop_comp", -1))
				if pci >= 0 and pci < comps.size():
					var pc: Dictionary = comps[pci]
					var dia := float(prop["d"])
					pc["size"] = Vector3(dia, dia, maxf(float((pc["size"] as Vector3).z), 0.02))
					for pm in pc["point_masses"]:
						pm["size"] = Vector3(dia, dia, maxf(float((pm["size"] as Vector3).z), 0.02))
					for shape in pc.get("shapes", []):
						if String(shape.get("type", "")) == "cyl":
							shape["r"] = dia * 0.48

	var m0 := 0.0
	var mz := 0.0
	for c in comps:
		for pm in c["point_masses"]:
			var m := float(pm["m"])
			m0 += m
			mz += m * (pm["pos"] as Vector3).z

	var radio_mass := 0.0 if etype in ["electric", "edf"] else float(definition["mass"]) * 0.09
	var pay := 0.0
	var pay_z := z_target
	var payload_kind := ""
	if etype in ["electric", "edf"]:
		var bats: Array = definition["batteries"]
		if not bats.is_empty():
			pay = float(bats[clampi(int(cfg.get("battery", 0)), 0, bats.size() - 1)]["mass"])
		payload_kind = "battery"
		pay_z = (z_target * (m0 + pay) - mz) / maxf(pay, 1e-4)
	else:
		var tank := float(definition["tank"])
		var dens := 0.74 if etype == "gas2" else 0.8
		pay = tank * dens * clampf(float(cfg.get("fuel", 1.0)), 0.05, 1.0)
		payload_kind = "fuel"
		pay_z = z_target - c_mac * 0.05

	var z_split := _plan_split(definition, length)
	var z_nose := _nose_split(definition, length)
	var first_station := float((definition["fuselage"] as Array)[0][0])
	var zmin := maxf(z_nose - length * 0.03, first_station + length * 0.04)
	var zmax := z_split - 0.02
	var core: Dictionary = comps[core_index]

	var radio_z := 0.0
	if radio_mass > 0.0:
		pay_z = clampf(z_target - c_mac * 0.05, zmin, zmax)
		var m_tank := m0 + pay
		var mz_tank := mz + pay * pay_z
		var rz := (z_target * (m_tank + radio_mass) - mz_tank) / radio_mass
		rz = clampf(rz, zmin, zmax)
		var rfp := _fus_param(definition, rz)
		(core["point_masses"] as Array).append({
			"pos": Vector3(0, float(rfp[2]) - float(rfp[1]) * 0.35, rz),
			"m": radio_mass,
			"size": Vector3(0.05, 0.05, 0.12),
			"radio": true,
		})
		m0 += radio_mass
		mz += radio_mass * rz
		radio_z = rz

	var free_lo := 0.0
	var free_hi := 0.0
	if payload_kind == "battery" and pay > 0.0:
		free_lo = (mz + pay * zmin) / (m0 + pay)
		free_hi = (mz + pay * zmax) / (m0 + pay)
	var cg_free := Vector2(
		(free_lo - zle) / maxf(c_mac, 1e-4),
		(free_hi - zle) / maxf(c_mac, 1e-4)
	)

	pay_z = clampf(pay_z, zmin, zmax)
	var pfp := _fus_param(definition, pay_z)
	(core["point_masses"] as Array).append({
		"pos": Vector3(0, float(pfp[2]) - float(pfp[1]) * 0.3, pay_z),
		"m": pay,
		"size": Vector3(0.05, 0.04, 0.12),
		"payload": true,
	})
	m0 += pay
	mz += pay * pay_z

	var ballast := 0.0
	var cgz := mz / maxf(m0, 1e-5)
	if absf(cgz - z_target) > 0.002:
		var bz := zmin if cgz > z_target else z_split - 0.05
		var need := m0 * (cgz - z_target) / (cgz - bz) if absf(cgz - bz) > 1e-4 else 0.0
		need = clampf(need, 0.0, float(definition["mass"]) * 0.18)
		if need > 0.0:
			ballast = need
			var bfp := _fus_param(definition, bz)
			(core["point_masses"] as Array).append({
				"pos": Vector3(0, float(bfp[2]), bz),
				"m": need,
				"size": Vector3(0.02, 0.02, 0.02),
				"ballast": true,
			})
			m0 += need
			mz += need * bz

	# Refresh component masses and total CG from the finalized point-mass set.
	var my := 0.0
	m0 = 0.0
	mz = 0.0
	for c in comps:
		var cm := 0.0
		for pm in c["point_masses"]:
			var m := float(pm["m"])
			cm += m
			m0 += m
			mz += m * (pm["pos"] as Vector3).z
			my += m * (pm["pos"] as Vector3).y
		c["mass"] = cm
	var cg := Vector3(0, my / maxf(m0, 1e-5), mz / maxf(m0, 1e-5))

	build["comps"] = comps
	build["mass"] = m0
	build["cg"] = cg
	build["payload_mass"] = pay
	build["payload_kind"] = payload_kind
	build["radio_mass"] = radio_mass
	build["radio_z"] = radio_z
	build["ballast"] = ballast
	build["cg_free"] = cg_free

	_update_gear_springs(build["wheels"], m0, cg.z)

static func _plan_split(definition: Dictionary, length: float) -> float:
	var tail_z := length * 0.75
	var htail: Dictionary = definition["htail"]
	if not htail.is_empty():
		tail_z = minf(tail_z, float(htail["z"]))
	for v in definition["vtails"]:
		tail_z = minf(tail_z, float(v["z"]))
	var wing_te := 0.0
	for w in definition["wings"]:
		wing_te = maxf(wing_te, float(w["z"]) + float(w["root"]))
	return clampf(lerpf(wing_te, tail_z, 0.45), length * 0.45, length * 0.9)

static func _nose_split(definition: Dictionary, length: float) -> float:
	var e0: Dictionary = definition["engines"][0]
	var ep: Vector3 = e0["pos"]
	if String(e0["type"]) in ["electric", "glow2", "glow4", "gas2"] and absf(ep.x) < 0.01 and ep.z < length * 0.2:
		return ep.z + length * 0.06
	return -1.0

static func _fus_param(definition: Dictionary, z: float) -> Array:
	var st: Array = definition["fuselage"]
	var n := st.size()
	if z <= float(st[0][0]):
		return [float(st[0][1]), float(st[0][2]), float(st[0][3]), float(st[0][4])]
	if z >= float(st[n - 1][0]):
		return [float(st[n - 1][1]), float(st[n - 1][2]), float(st[n - 1][3]), float(st[n - 1][4])]
	var k := 0
	while k < n - 2 and z > float(st[k + 1][0]):
		k += 1
	var z0 := float(st[k][0])
	var z1 := float(st[k + 1][0])
	var t := (z - z0) / maxf(z1 - z0, 1e-5)
	var out := []
	for component in [1, 2, 3, 4]:
		var p0 := float(st[maxi(k - 1, 0)][component])
		var p1 := float(st[k][component])
		var p2 := float(st[k + 1][component])
		var p3 := float(st[mini(k + 2, n - 1)][component])
		var v := 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t * t * t)
		if component != 3:
			v = maxf(v, 0.0015)
		out.append(v)
	return out

static func _update_gear_springs(wheels: Array, total_mass: float, cg_z: float) -> void:
	if wheels.is_empty():
		return
	var ahead := []
	var behind := []
	for w in wheels:
		if (w["center"] as Vector3).z < cg_z:
			ahead.append(w)
		else:
			behind.append(w)
	var za := 0.0
	var zb := 0.0
	for w in ahead:
		za += (w["center"] as Vector3).z / ahead.size()
	for w in behind:
		zb += (w["center"] as Vector3).z / behind.size()
	var share_a := 0.5
	if not ahead.is_empty() and not behind.is_empty():
		share_a = clampf((zb - cg_z) / maxf(zb - za, 1e-3), 0.05, 0.95)
	elif ahead.is_empty():
		share_a = 0.0
	else:
		share_a = 1.0
	for w in wheels:
		var grp := ahead if (w["center"] as Vector3).z < cg_z else behind
		var share := (share_a if grp == ahead else 1.0 - share_a) / maxf(grp.size(), 1)
		var load := maxf(total_mass * 9.81 * share, total_mass * 9.81 * 0.04)
		var static_defl := float(w["travel"]) * 0.35
		var k := load / static_defl * float(w["k_scale"])
		w["k"] = k
		w["c"] = 2.0 * 0.55 * sqrt(k * load / 9.81)
		w["load"] = load
