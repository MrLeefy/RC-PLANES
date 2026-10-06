extends Node
## Dev tool: dumps each aircraft's planform geometry as JSON for outline-fit comparison against reference three-views.
##   godot --headless --path . res://tests/planform_dump.tscn -- /path/out.json
func _ready() -> void:
	var out := {}
	for d in AircraftDB.all():
		var o := {"length": d["length"], "fus": d["fuselage"], "wings": [], "htail": {}, "vtails": []}
		for w in d["wings"]:
			o["wings"].append({"z": w["z"], "span": w["span"], "root": w["root"], "tip": w["tip"], "sweep": w["sweep"], "x0": w.get("x0", 0.0)})
		var h: Dictionary = d["htail"]
		if not h.is_empty():
			o["htail"] = {"z": h["z"], "span": h["span"], "root": h["root"], "tip": h["tip"], "sweep": h["sweep"]}
		for v in d["vtails"]:
			o["vtails"].append({"z": v["z"], "y": v["y"], "x": v.get("x", 0.0), "height": v["height"], "root": v["root"], "tip": v["tip"], "sweep": v["sweep"], "cant": v.get("cant", 0.0), "mirror": v.get("mirror", false)})
		var engs := []
		for e in d["engines"]:
			var p: Vector3 = e["pos"]
			engs.append([p.x, p.z, (e.get("nacelle", {}) as Dictionary).get("len", 0.0), (e.get("nacelle", {}) as Dictionary).get("r", 0.0)])
		o["engines"] = engs
		out[d["id"]] = o
	var args := OS.get_cmdline_user_args()
	var f := FileAccess.open(args[0], FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	get_tree().quit()
