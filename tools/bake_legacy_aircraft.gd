extends SceneTree
## Offline-only legacy aircraft baker.
##
## Run:
##   godot --headless --path . --script res://tools/bake_legacy_aircraft.gd
## Optional:
##   --aircraft=skylark
##
## Produces a binary PackedScene plus a binary physics blueprint per aircraft.
## Shipping builds load these directly and skip procedural mesh construction.

const OUT_DIR := "res://assets/aircraft_baked"
const BakedBlueprint = preload("res://scripts/aircraft/aircraft_baked_blueprint.gd")

func _initialize() -> void:
	call_deferred("_run")

func _default_cfg() -> Dictionary:
	return {"battery": 0, "prop": 0, "cg": 0.0, "throws": "high", "fuel": 1.0, "engine": 0}

func _requested_aircraft() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--aircraft="):
			return arg.trim_prefix("--aircraft=")
	return ""

func _set_scene_owners(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		_set_scene_owners(child, scene_root)

func _run() -> void:
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	var mk := DirAccess.make_dir_recursive_absolute(abs_dir)
	if mk != OK:
		push_error("Cannot create %s: %s" % [OUT_DIR, error_string(mk)])
		quit(2)
		return

	var requested := _requested_aircraft()
	var total_us := 0
	var built := 0
	for definition in AircraftDB.all():
		var id := String(definition["id"])
		if requested != "" and id != requested:
			continue

		var start_us := Time.get_ticks_usec()
		var builder := AircraftBuilder.new()
		var build := builder.build(definition, _default_cfg(), 2)
		var root := build["root"] as Node3D
		root.name = "Visual"
		_set_scene_owners(root, root)

		var bp = BakedBlueprint.capture(build, builder.body_drag, root, id, 2)
		var bp_err := ResourceSaver.save(bp, "%s/%s.res" % [OUT_DIR, id], ResourceSaver.FLAG_COMPRESS)
		if bp_err != OK:
			push_error("Blueprint save failed for %s: %s" % [id, error_string(bp_err)])
			root.free()
			quit(3)
			return

		var packed := PackedScene.new()
		var pack_err := packed.pack(root)
		if pack_err != OK:
			push_error("Scene pack failed for %s: %s" % [id, error_string(pack_err)])
			root.free()
			quit(4)
			return
		var scene_err := ResourceSaver.save(packed, "%s/%s.scn" % [OUT_DIR, id], ResourceSaver.FLAG_COMPRESS)
		if scene_err != OK:
			push_error("Scene save failed for %s: %s" % [id, error_string(scene_err)])
			root.free()
			quit(5)
			return

		var elapsed := Time.get_ticks_usec() - start_us
		total_us += elapsed
		built += 1
		print("BAKED %s in %.1f ms -> %s" % [id, elapsed / 1000.0, OUT_DIR])
		root.free()

	if built == 0:
		push_error("No aircraft matched '%s'" % requested)
		quit(6)
		return
	print("BAKE COMPLETE: %d aircraft, %.1f ms total" % [built, total_us / 1000.0])
	quit()
