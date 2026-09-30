# Dev tool: prints LOD0 triangle count per aircraft.  godot --headless --path . -s res://tests/tri_count.gd
extends SceneTree
func _initialize():
	var tot := 0
	for d in AircraftDB.all():
		var b := AircraftBuilder.new()
		var build = b.build(d, {"battery":0,"prop":0,"cg":0.0,"throws":"high","fuel":1.0}, 2)
		var n := 0
		var stack := [build["root"]]
		while stack.size() > 0:
			var nd: Node = stack.pop_back()
			for c in nd.get_children():
				stack.append(c)
			if nd is MeshInstance3D and nd.mesh:
				for s in nd.mesh.get_surface_count():
					var arr = nd.mesh.surface_get_arrays(s)
					n += (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		print("%-12s %7d tris" % [d["id"], n])
		tot += n
	print("TOTAL ", tot)
	quit()
