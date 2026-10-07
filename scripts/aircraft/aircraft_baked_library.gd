class_name AircraftBakedLibrary
extends RefCounted
## Runtime loader for offline-baked aircraft. A baked hit avoids all procedural
## mesh construction in AircraftBuilder.

const ROOT := "res://assets/aircraft_baked"
const BakedBlueprint = preload("res://scripts/aircraft/aircraft_baked_blueprint.gd")
const RuntimeConfig = preload("res://scripts/aircraft/aircraft_runtime_config.gd")

static func has_baked(id: String, detail := 2) -> bool:
	if detail != 2:
		return false
	return ResourceLoader.exists("%s/%s.scn" % [ROOT, id]) and ResourceLoader.exists("%s/%s.res" % [ROOT, id])

static func instantiate(definition: Dictionary, cfg: Dictionary, detail := 2) -> Dictionary:
	if detail != 2:
		return {}
	var id := String(definition["id"])
	if not has_baked(id, detail):
		return {}

	var scene_path := "%s/%s.scn" % [ROOT, id]
	var legacy_path := "res://assets/aircraft_legacy/%s.scn" % id
	if bool(cfg.get("legacy_model", false)) and ResourceLoader.exists(legacy_path):
		scene_path = legacy_path
	var packed := ResourceLoader.load(scene_path) as PackedScene
	var blueprint = ResourceLoader.load("%s/%s.res" % [ROOT, id])
	if packed == null or blueprint == null or blueprint.format_version != 1:
		return {}
	if blueprint.source_aircraft_id != id or blueprint.source_detail != detail:
		return {}

	var root := packed.instantiate() as Node3D
	if root == null:
		return {}
	var build: Dictionary = blueprint.call("instantiate_build", root)
	RuntimeConfig.apply(build, definition, cfg)
	return {
		"build": build,
		"body_drag": blueprint.body_drag.duplicate(true),
		"baked": true,
	}

static func mode_for(definition: Dictionary, cfg: Dictionary, detail := 2) -> String:
	return "baked" if detail == 2 and has_baked(String(definition["id"]), detail) else "procedural_fallback"
