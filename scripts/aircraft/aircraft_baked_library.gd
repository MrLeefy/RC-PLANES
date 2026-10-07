class_name AircraftBakedLibrary
extends RefCounted
## Runtime loader for offline-baked aircraft. A baked hit avoids all procedural
## mesh construction in AircraftBuilder.

const ROOT := "res://assets/aircraft_baked"
const BakedBlueprint = preload("res://scripts/aircraft/aircraft_baked_blueprint.gd")

static func _default_cfg(cfg: Dictionary) -> bool:
	return (
		int(cfg.get("battery", 0)) == 0
		and int(cfg.get("prop", 0)) == 0
		and int(cfg.get("engine", 0)) == 0
		and absf(float(cfg.get("cg", 0.0))) < 0.00001
		and String(cfg.get("throws", "high")) == "high"
		and absf(float(cfg.get("fuel", 1.0)) - 1.0) < 0.00001
	)

static func has_baked(id: String, detail := 2) -> bool:
	if detail != 2:
		return false
	return ResourceLoader.exists("%s/%s.scn" % [ROOT, id]) and ResourceLoader.exists("%s/%s.res" % [ROOT, id])

static func instantiate(definition: Dictionary, cfg: Dictionary, detail := 2) -> Dictionary:
	# First implementation is exact for the shipped/default workshop setup.
	# Non-default mass/prop/CG variants deliberately stay on the legacy path until
	# the lightweight runtime configuration delta layer is complete.
	if detail != 2 or not _default_cfg(cfg):
		return {}
	var id := String(definition["id"])
	if not has_baked(id, detail):
		return {}

	var packed := ResourceLoader.load("%s/%s.scn" % [ROOT, id]) as PackedScene
	var blueprint = ResourceLoader.load("%s/%s.res" % [ROOT, id])
	if packed == null or blueprint == null or blueprint.format_version != 1:
		return {}
	if blueprint.source_aircraft_id != id or blueprint.source_detail != detail:
		return {}

	var root := packed.instantiate() as Node3D
	if root == null:
		return {}
	var build := blueprint.instantiate_build(root)
	return {
		"build": build,
		"body_drag": blueprint.body_drag.duplicate(true),
		"baked": true,
	}

static func mode_for(definition: Dictionary, cfg: Dictionary, detail := 2) -> String:
	return "baked" if detail == 2 and _default_cfg(cfg) and has_baked(String(definition["id"]), detail) else "procedural_fallback"
