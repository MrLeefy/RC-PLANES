extends SceneTree
const BakedLibrary = preload("res://scripts/aircraft/aircraft_baked_library.gd")
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for definition in AircraftDB.all():
		var id := String(definition["id"])
		var loaded := BakedLibrary.instantiate(definition, {}, 2)
		if loaded.is_empty():
			failures += 1
			continue
		var build: Dictionary = loaded["build"]
		for comp in build["comps"]:
			if comp["visual"] == null: failures += 1
		for part in build["parts"]:
			if part["node"] == null: failures += 1
		var triangles := _check_meshes(build["root"])
		if triangles == 0: failures += 1
		if id in ["skyliner", "cargo130"]:
			var legacy := BakedLibrary.instantiate(definition, {"legacy_model": true}, 2)
			if legacy.is_empty() or (build["root"] as Node).get_node_or_null("canopy/FramedWindshield") == null:
				failures += 1
			else:
				if (legacy["build"]["root"] as Node).get_node_or_null("canopy/FramedWindshield") != null:
					failures += 1
				if build["mass"] != legacy["build"]["mass"] or build["cg"] != legacy["build"]["cg"]:
					failures += 1
				(legacy["build"]["root"] as Node).free()
		print("STATIC %s: %d LOD0 triangles; paths, mesh data and fallback checked" % [id, triangles])
		(build["root"] as Node).free()
	print("STATIC FLEET TEST aircraft=16 failures=%d" % failures)
	quit(0 if failures == 0 else 1)

func _check_meshes(node: Node) -> int:
	var triangles := 0
	if node is MeshInstance3D:
		var mesh := (node as MeshInstance3D).mesh
		if mesh != null:
			for surface in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				triangles += indices.size() / 3
				for point in vertices:
					if not point.is_finite(): failures += 1
				for normal in normals:
					if not normal.is_finite() or normal.length_squared() < 0.5: failures += 1
				for index in indices:
					if index < 0 or index >= vertices.size(): failures += 1
	for child in node.get_children():
		triangles += _check_meshes(child)
	return triangles
