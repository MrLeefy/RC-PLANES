extends Node
func _ready():
	var id := OS.get_cmdline_user_args()[0]
	var ac := Aircraft.new()
	ac.setup(AircraftDB.by_id(id), {}, 0, true)
	var tot := 0.0
	var mz := 0.0
	for c in ac.comps:
		for pm in c["point_masses"]:
			var m: float = pm["m"]
			var z: float = (pm["pos"] as Vector3).z
			tot += m; mz += m * z
			print("%-14s %-9s m=%.3f z=%.3f y=%.3f %s" % [c["id"], c["kind"], m, z, (pm["pos"] as Vector3).y, "PAYLOAD" if pm.get("payload", false) else ""])
	print("total ", tot, " cgz ", mz / tot, " mac ", ac.build["mac"], " ballast ", ac.build["ballast"])
	get_tree().quit()
