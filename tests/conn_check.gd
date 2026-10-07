extends Node
## Dev tool: per aircraft, flags components whose bounding box does not touch their parent's (floating parts) and
## wheels / struts whose top does not touch the fuselage or wing. godot --headless --path . res://tests/conn_check.tscn
func _aabb_gap(a_min: Vector3, a_max: Vector3, b_min: Vector3, b_max: Vector3) -> float:
	var gx := maxf(maxf(a_min.x - b_max.x, b_min.x - a_max.x), 0.0)
	var gy := maxf(maxf(a_min.y - b_max.y, b_min.y - a_max.y), 0.0)
	var gz := maxf(maxf(a_min.z - b_max.z, b_min.z - a_max.z), 0.0)
	return Vector3(gx, gy, gz).length()
func _ready() -> void:
	var total := 0
	for d in AircraftDB.all():
		var b := AircraftBuilder.new()
		var r := b.build(d, Settings.aircraft_cfg(d["id"]), 2)
		var comps: Array = r["comps"]
		for i in comps.size():
			var c: Dictionary = comps[i]
			var p := int(c["parent"])
			if p < 0 or (c["aabb_min"] as Vector3).x > 1e8:
				continue
			var par: Dictionary = comps[p]
			var gap := _aabb_gap(c["aabb_min"], c["aabb_max"], par["aabb_min"], par["aabb_max"])
			if gap > 0.004:
				print("GAP %-11s %-12s (%s) %.1f mm from parent %s" % [d["id"], c["id"], c["kind"], gap * 1000.0, par["id"]])
				total += 1
		for w in r["wheels"]:
			var top: Vector3 = w["top"]
			var fus: Dictionary = comps[0]
			var inside := false
			for k in comps.size():
				var cc: Dictionary = comps[k]
				if String(cc["kind"]) in ["fuselage", "wing", "wingtip", "nacelle", "engine"]:
					var mn: Vector3 = (cc["aabb_min"] as Vector3) - Vector3(0.012, 0.012, 0.012)
					var mx: Vector3 = (cc["aabb_max"] as Vector3) + Vector3(0.012, 0.012, 0.012)
					if top.x >= mn.x and top.x <= mx.x and top.y >= mn.y and top.y <= mx.y and top.z >= mn.z and top.z <= mx.z:
						inside = true
						break
			if not inside:
				print("GEAR %-11s wheel top %s not attached to any airframe part" % [d["id"], str(top.snapped(Vector3(0.001, 0.001, 0.001)))])
				total += 1
		# wheels overlapping each other (hub-to-hub distance less than the sum of radii in the wheel plane)
		var wl: Array = r["wheels"]
		for i in wl.size():
			for j in range(i + 1, wl.size()):
				var ci: Vector3 = wl[i]["center"]
				var cj: Vector3 = wl[j]["center"]
				var dd := Vector2(ci.y - cj.y, ci.z - cj.z).length()
				if absf(ci.x - cj.x) < 0.5 * (float(wl[i]["w"]) + float(wl[j]["w"])) and dd < float(wl[i]["r"]) + float(wl[j]["r"]) - 0.002:
					print("WHEEL %-11s wheels %d and %d overlap (%.0f mm apart)" % [d["id"], i, j, dd * 1000.0])
					total += 1
		# propeller discs sweeping through airframe parts that are not their own engine
		var engs: Array = d["engines"]
		for ei in engs.size():
			var e: Dictionary = engs[ei]
			if not String(e["type"]) in ["electric", "glow2", "glow4", "gas2"]:
				continue
			var ep: Vector3 = e["pos"]
			var pr: float = float(e.get("prop_d", 0.3)) * 0.5
			var pd: Array = d["props"]
			if pd.size() > 0:
				pr = 0.0
				for po in pd:
					pr = maxf(pr, float(po["d"]) * 0.5)
			for ci2 in comps.size():
				var c2: Dictionary = comps[ci2]
				if not String(c2["kind"]) in ["wing", "wingtip", "stab", "fin", "fuselage", "canopy"]:
					continue
				var mn2: Vector3 = c2["aabb_min"]
				var mx2: Vector3 = c2["aabb_max"]
				if mn2.x > 1e8:
					continue
				# the disc plane slab is z in [ep.z-0.025, ep.z+0.025]; does the part reach the circle?
				if mx2.z < ep.z - 0.025 or mn2.z > ep.z + 0.025:
					continue
				var nx: float = clampf(ep.x, mn2.x, mx2.x)
				var ny: float = clampf(ep.y, mn2.y, mx2.y)
				var inner := Vector2(nx - ep.x, ny - ep.y).length()
				if inner < pr * 0.98 and not (String(c2["kind"]) == "fuselage" and absf(ep.x) < 0.01):
					print("PROP  %-11s prop %d (r %.0f mm) sweeps %s %.0f mm inside" % [d["id"], ei, pr * 1000.0, c2["id"], (pr - inner) * 1000.0])
					total += 1
		r["root"].free()
	print("TOTAL issues: ", total)
	get_tree().quit()
