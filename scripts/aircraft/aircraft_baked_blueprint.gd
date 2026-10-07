class_name AircraftBakedBlueprint
extends Resource
## Serializable runtime blueprint for an aircraft whose visual geometry was built
## offline. The expensive AircraftBuilder mesh path is not needed at runtime.

@export var build_data: Dictionary = {}
@export var body_drag: Dictionary = {}
@export var component_paths: Array[NodePath] = []
@export var part_paths: Array[NodePath] = []
@export var fracture_node_paths: Array = []
@export var source_aircraft_id := ""
@export var source_detail := 2
@export var format_version := 1

static func capture(source_build: Dictionary, drag: Dictionary, root: Node3D, aircraft_id: String, detail: int) -> AircraftBakedBlueprint:
	var bp := AircraftBakedBlueprint.new()
	bp.source_aircraft_id = aircraft_id
	bp.source_detail = detail
	bp.body_drag = drag.duplicate(true)

	var clean := {}
	for key in source_build.keys():
		if key in ["root", "comps", "parts", "fractures"]:
			continue
		clean[key] = source_build[key].duplicate(true) if source_build[key] is Array or source_build[key] is Dictionary else source_build[key]

	var comps_out := []
	for comp in source_build["comps"]:
		var c: Dictionary = (comp as Dictionary).duplicate(true)
		var visual := c.get("visual") as Node
		bp.component_paths.append(root.get_path_to(visual) if visual else NodePath(""))
		c.erase("visual")
		comps_out.append(c)
	clean["comps"] = comps_out

	var parts_out := []
	for part in source_build["parts"]:
		var p: Dictionary = part as Dictionary
		var node := p.get("node") as Node
		bp.part_paths.append(root.get_path_to(node) if node else NodePath(""))
		# Runtime animation only needs the node, origin and owning component.
		parts_out.append({
			"origin": p.get("origin", Vector3.ZERO),
			"comp": int(p.get("comp", -1)),
		})
	clean["parts"] = parts_out

	var fractures_out := []
	for fracture in source_build.get("fractures", []):
		var f: Dictionary = (fracture as Dictionary).duplicate(true)
		var paths := []
		for n in f.get("nodes", []):
			paths.append(root.get_path_to(n as Node))
		bp.fracture_node_paths.append(paths)
		f.erase("nodes")
		fractures_out.append(f)
	clean["fractures"] = fractures_out

	bp.build_data = clean
	return bp

func instantiate_build(root: Node3D) -> Dictionary:
	var out: Dictionary = build_data.duplicate(true)

	var comps: Array = out.get("comps", [])
	for i in comps.size():
		var path := component_paths[i] if i < component_paths.size() else NodePath("")
		comps[i]["visual"] = root.get_node_or_null(path)
	out["comps"] = comps

	var parts: Array = out.get("parts", [])
	for i in parts.size():
		var path := part_paths[i] if i < part_paths.size() else NodePath("")
		parts[i]["node"] = root.get_node_or_null(path)
	out["parts"] = parts

	var fractures: Array = out.get("fractures", [])
	for i in fractures.size():
		var nodes := []
		var paths: Array = fracture_node_paths[i] if i < fracture_node_paths.size() else []
		for path in paths:
			var node := root.get_node_or_null(path)
			if node:
				nodes.append(node)
		fractures[i]["nodes"] = nodes
	out["fractures"] = fractures

	out["root"] = root
	return out
