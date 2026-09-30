extends Node
func _ready():
	var bad := 0
	for f in _scan("res://scripts") + _scan("res://tests"):
		var s = load(f)
		if s == null or not (s as Script).can_instantiate():
			print("FAIL ", f); bad += 1
	print("CHECK DONE bad=", bad)
	get_tree().quit()
func _scan(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	for f in d.get_files():
		if f.ends_with(".gd"): out.append(dir + "/" + f)
	for sd in d.get_directories():
		out.append_array(_scan(dir + "/" + sd))
	return out
