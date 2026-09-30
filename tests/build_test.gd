extends Node
func _ready():
	var t0 := Time.get_ticks_msec()
	for d in AircraftDB.all():
		var t := Time.get_ticks_usec()
		var b := AircraftBuilder.new()
		var r := b.build(d, Settings.aircraft_cfg(d["id"]), 2)
		var tris := 0
		for p in b.parts:
			for k in p["kits"].values():
				tris += k.tri_count()
		print("%-12s comps=%2d panels=%2d surf=%2d eng=%d wheels=%d mass=%.2f cg=(%.3f,%.3f) mac=%.3f ballast=%.2f tris=%d  %.1fms" % [d["id"], b.comps.size(), b.panels.size(), b.surfaces.size(), b.engines.size(), b.wheels.size(), r["mass"], r["cg"].y, r["cg"].z, r["mac"]["c"], b.ballast, tris, (Time.get_ticks_usec()-t)/1000.0])
		r["root"].free()
	print("total ms ", Time.get_ticks_msec() - t0)
	get_tree().quit()