extends SceneTree
## Offline artwork edit only. Preserves the legacy physics blueprint, component
## hierarchy and animation pivots. Uses immutable legacy scenes as its input.
## Run after bake_legacy_aircraft.gd when rebuilding the full static fleet.

const RuntimeConfig = preload("res://scripts/aircraft/aircraft_runtime_config.gd")
const LEGACY := "res://assets/aircraft_legacy"
var changed_vertices := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var profiles: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/aircraft_art/transport_noses.json"))
	DirAccess.make_dir_recursive_absolute(LEGACY)
	for id in ["skyliner", "cargo130"]:
		var source := "%s/%s.scn" % [LEGACY, id]
		var target := "res://assets/aircraft_baked/%s.scn" % id
		if not FileAccess.file_exists(source):
			var copy_error := DirAccess.copy_absolute(target, source)
			if copy_error != OK:
				push_error("Cannot preserve legacy scene %s" % id)
				quit(1)
				return
		var model := (load(source) as PackedScene).instantiate() as Node3D
		var definition := AircraftDB.by_id(id)
		var visual_definition := definition.duplicate(true)
		visual_definition["fuselage"] = profiles[id]["stations"]
		var body := model.get_node("fuselage/Mesh") as MeshInstance3D
		body.mesh = _reshape_mesh(body.mesh as ArrayMesh, definition, visual_definition, id)
		var canopy := model.get_node("canopy") as Node3D
		for child in canopy.get_children():
			if child is MeshInstance3D:
				(child as MeshInstance3D).visible = false
		_add_windshield(canopy, visual_definition, profiles[id], id)
		_set_owners(model, model)
		var packed := PackedScene.new()
		if packed.pack(model) != OK or ResourceSaver.save(packed, target, ResourceSaver.FLAG_COMPRESS) != OK:
			push_error("Failed saving refined scene %s" % id)
			quit(1)
			return
		print("REFINED %s: nose loft and framed cockpit; legacy physics unchanged" % id)
		model.free()
	print("TRANSPORT ART PASS: modified %d vertices; two static scenes saved" % changed_vertices)
	quit()

func _warp(point: Vector3, definition: Dictionary, visual: Dictionary) -> Vector3:
	if point.z > 0.98:
		return point
	var old := RuntimeConfig._fus_param(definition, point.z)
	var revised := RuntimeConfig._fus_param(visual, point.z)
	var reshaped := Vector3(point.x * float(revised[0]) / float(old[0]),
		(point.y - float(old[2])) * float(revised[1]) / float(old[1]) + float(revised[2]), point.z)
	return reshaped.lerp(point, smoothstep(0.78, 0.98, point.z))

func _reshape_mesh(source: ArrayMesh, definition: Dictionary, visual: Dictionary, id: String) -> ArrayMesh:
	var importer := ImporterMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for i in vertices.size():
			var point := vertices[i]
			if point.z > 0.98:
				continue
			var warped := _warp(point, definition, visual)
			var h := 0.0001
			var jacobian := Basis(
				(_warp(point + Vector3(h, 0, 0), definition, visual) - warped) / h,
				(_warp(point + Vector3(0, h, 0), definition, visual) - warped) / h,
				(_warp(point + Vector3(0, 0, h), definition, visual) - warped) / h)
			vertices[i] = warped
			if not normals.is_empty() and absf(jacobian.determinant()) > 0.0001:
				normals[i] = (jacobian.inverse().transposed() * normals[i]).normalized()
			if not colors.is_empty() and id == "skyliner" and point.z < 0.065:
				colors[i] = Color(0.84, 0.86, 0.88, colors[i].a)
			changed_vertices += 1
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		importer.add_surface(source.surface_get_primitive_type(surface), arrays, [], {}, source.surface_get_material(surface))
	# Regenerate offline simplification LODs after changing the silhouette.
	importer.generate_lods(60.0, 60.0, [])
	return importer.get_mesh()

func _window_point(theta: float, z: float, visual: Dictionary, offset := 1.09) -> Vector3:
	var profile := RuntimeConfig._fus_param(visual, z)
	var exponent := 2.0 / float(profile[3])
	return Vector3(signf(sin(theta)) * pow(absf(sin(theta)), exponent) * float(profile[0]) * offset,
		float(profile[2]) + pow(cos(theta), exponent) * float(profile[1]) * offset, z)

func _add_windshield(canopy: Node3D, visual: Dictionary, profile: Dictionary, id: String) -> void:
	var glass := MeshKit.new()
	var frames := MeshKit.new()
	var angles := [-1.20, -0.80, -0.40, 0.0, 0.40, 0.80, 1.20]
	var frame_color := Color(0.73, 0.75, 0.77) if id == "skyliner" else Color(0.32, 0.34, 0.35)
	for i in range(angles.size() - 1):
		var a := float(angles[i])
		var b := float(angles[i + 1])
		var sweep := float(profile["cockpit_sweep"])
		var p0 := _window_point(a, float(profile["cockpit_front_z"]) + absf(a) * sweep, visual)
		var p1 := _window_point(b, float(profile["cockpit_front_z"]) + absf(b) * sweep, visual)
		var p2 := _window_point(b, float(profile["cockpit_back_z"]) + absf(b) * sweep, visual)
		var p3 := _window_point(a, float(profile["cockpit_back_z"]) + absf(a) * sweep, visual)
		glass.add_quad(p0, p1, p2, p3, Color(0.035, 0.070, 0.105), false, Vector3(0, 0.7, -0.7))
		for edge in [[p0, p1], [p1, p2], [p2, p3], [p3, p0]]:
			frames.add_cylinder(edge[0], edge[1], 0.0014, 0.0014, 5, MeshKit.const_color(frame_color), false)
	if id == "skyliner":
		for side in [-1.0, 1.0]:
			for i in 6:
				var z := 0.29 + i * 0.048
				var p0 := _window_point(side * 0.96, z, visual, 1.025)
				var p1 := _window_point(side * 0.96, z + 0.013, visual, 1.025)
				var p2 := _window_point(side * 1.06, z + 0.013, visual, 1.025)
				var p3 := _window_point(side * 1.06, z, visual, 1.025)
				glass.add_quad(p0, p1, p2, p3, Color(0.035, 0.070, 0.105), false, Vector3(side, 0, 0))
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.22
	material.metallic = 0.25
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := ArrayMesh.new()
	glass.append_to(mesh, material)
	var trim_material := material.duplicate() as StandardMaterial3D
	trim_material.roughness = 0.55
	frames.append_to(mesh, trim_material)
	var instance := MeshInstance3D.new()
	instance.name = "FramedWindshield"
	instance.mesh = mesh
	canopy.add_child(instance)

func _set_owners(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		_set_owners(child, scene_root)
