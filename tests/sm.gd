extends Node
func _ready():
	for d in AircraftDB.all():
		var a := Aircraft.new()
		a.setup(d, {}, 0, true)
		print("%-11s static_margin=%.2f MAC  pitch_trim=%.2f roll_trim=%.2f" % [d["id"], a.static_margin(), a.pitch_trim, a.roll_trim])
		a.free()
	get_tree().quit()
