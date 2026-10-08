extends "res://tests/test_runner.gd"
## Dev tool: how many mesh instances / surfaces / triangles does each aircraft cost to draw?
## RC_SUITE=res://tests/draw_probe.gd godot --headless --path . -- --test

func _run_all() -> void:
	var tot_mi := 0
	for d in AircraftDB.all():
		var id := String(d["id"])
		var a := await _spawn(id)
		var mis := a.find_children("*", "MeshInstance3D", true, false)
		var surfaces := 0
		var tris := 0
		var small := 0
		var casters := 0
		var span := 0.0
		for m in mis:
			var mi := m as MeshInstance3D
			if mi.mesh == null or not mi.is_visible_in_tree():
				continue
			surfaces += mi.mesh.get_surface_count()
			for s in mi.mesh.get_surface_count():
				var arr := mi.mesh.surface_get_arrays(s)
				var idx = arr[Mesh.ARRAY_INDEX]
				tris += (idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			var sz := mi.get_aabb().size * mi.global_transform.basis.get_scale()
			if maxf(sz.x, maxf(sz.y, sz.z)) < 0.12 * float(d.get("span", 1.5)):
				small += 1
			if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				casters += 1
		tot_mi += mis.size()
		print("DRAW %-10s meshes %3d surfaces %3d tris %6d small(<12%% span) %3d shadow casters %3d comps %3d" % [id, mis.size(), surfaces, tris, small, casters, a.comps.size()])
	print("DRAW total meshes ", tot_mi)
