extends Node
## Persistent, versioned settings store.
## - Deep-merges saved data over defaults key-by-key (legit zero values survive).
## - Corrupted files are backed up and replaced by defaults, never crash the game.
## - Versioned migrations keep old saves working after updates.

signal changed(section: String)

const SAVE_PATH := "user://rcpark_settings.json"
const SAVE_VERSION := 3

const TX_PRESETS := {
	"Gentle": {
		"roll": {"expo": 0.45, "rate": 0.75, "dz": 0.03, "trim": 0.0},
		"pitch": {"expo": 0.45, "rate": 0.75, "dz": 0.03, "trim": 0.0},
		"yaw": {"expo": 0.35, "rate": 0.85, "dz": 0.03, "trim": 0.0},
		"smoothing": 0.10,
	},
	"Balanced": {
		"roll": {"expo": 0.30, "rate": 0.90, "dz": 0.02, "trim": 0.0},
		"pitch": {"expo": 0.30, "rate": 0.90, "dz": 0.02, "trim": 0.0},
		"yaw": {"expo": 0.20, "rate": 1.00, "dz": 0.02, "trim": 0.0},
		"smoothing": 0.05,
	},
	"Linear / Direct": {
		"roll": {"expo": 0.0, "rate": 1.0, "dz": 0.0, "trim": 0.0},
		"pitch": {"expo": 0.0, "rate": 1.0, "dz": 0.0, "trim": 0.0},
		"yaw": {"expo": 0.0, "rate": 1.0, "dz": 0.0, "trim": 0.0},
		"smoothing": 0.0,
	},
}

var data: Dictionary = {}
var load_status := "defaults"
var last_save_error := ""
var future_version := false
signal save_failed(message: String)

func defaults() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"transmitter": {
			"active_profile": "Balanced",
			"profiles": TX_PRESETS.duplicate(true),
			"per_aircraft": {},
		},
		"controls": {
			"mode": 2, "stick_size": 1.0, "opacity": 0.55, "floating": false, "large_telemetry": false,
			"left_handed": false, "throttle_brake": true, "haptics": true,
		},
		"graphics": {
			"quality": "high", "render_scale": 0.85, "fps": 60, "auto_scale": true, "adaptive_physics": true,
			"grass": 1.0, "show_fps": false, "msaa": 1,
		},
		"audio": {"master": 0.9, "engine": 1.0, "effects": 1.0, "ambience": 0.6},
		"gameplay": {
			"assist": "sport", "damage": "physical", "aftermath": 4.0, "slowmo": 0.3,
			"landing_feedback": true, "camera": "pilot", "auto_zoom": true, "units": "metric",
			"killcam": true,
		},
		"environment": {"time": "golden", "wind": "light", "wind_dir": "headwind"},
		"aircraft_cfg": {},
		"last_aircraft": "skylark",
		"last_mode": "free",
		"records": {},
	}

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	data = defaults()
	future_version = false
	load_status = "defaults"
	for candidate in [SAVE_PATH, SAVE_PATH + ".bak", SAVE_PATH + ".tmp"]:
		var result := SafeStore.read_json(candidate, 1024 * 1024)
		if not result.get("ok", false):
			continue
		var parsed: Dictionary = result["data"]
		var version := SafeStore.number(parsed.get("version", 1), 1, 1, 100000)
		if version > SAVE_VERSION:
			# Never overwrite a newer app's preferences with an older schema.
			future_version = true
			load_status = "newer_version_read_only"
			return
		data = validate(migrate(parsed))
		load_status = "loaded" if candidate == SAVE_PATH else "recovered_" + candidate.get_extension()
		return
	if FileAccess.file_exists(SAVE_PATH):
		load_status = "corrupt_reset"
		# Preserve the corrupt original; defaults remain in memory until a real save.
	else:
		# First launch: pick a graphics preset that fits this phone. The player can change it any time.
		var tier := device_tier(int(OS.get_memory_info().get("physical", 0)) / (1024 * 1024), OS.get_processor_count(),
			RenderingServer.get_video_adapter_name() if DisplayServer.get_name() != "headless" else "", OS.has_feature("mobile"))
		data["graphics"].merge(tier_graphics(tier), true)

## 2 = flagship, 1 = mid-range, 0 = entry level. Desktop and unknown hardware count as flagship.
static func device_tier(mem_mb: int, cores: int, adapter: String, mobile: bool) -> int:
	if not mobile:
		return 2
	var gpu := adapter.to_lower()
	# Adreno 7xx, Mali-G7xx / G715+, Immortalis, Apple GPUs: current high-end parts
	var fast_gpu := false
	for key in ["adreno (tm) 7", "adreno 7", "immortalis", "mali-g7", "mali-g8", "apple"]:
		if gpu.contains(key):
			fast_gpu = true
	if mem_mb >= 7000 and cores >= 8 and fast_gpu:
		return 2
	if mem_mb >= 4500 and cores >= 6:
		return 1
	return 0

static func tier_graphics(tier: int) -> Dictionary:
	match tier:
		2: return {"quality": "high", "render_scale": 0.85, "grass": 1.0}
		1: return {"quality": "high", "render_scale": 0.7, "grass": 0.7}
	return {"quality": "performance", "render_scale": 0.6, "grass": 0.4}

func _backup_corrupt(txt: String) -> void:
	var f := FileAccess.open(SAVE_PATH + ".corrupt.bak", FileAccess.WRITE)
	if f:
		f.store_string(txt)
		f.close()

## Migrations: each step upgrades one version. Unknown future keys are kept.
func migrate(d: Dictionary) -> Dictionary:
	var v := int(SafeStore.number(d.get("version", 1), 1, 1, 100000))
	if v < 2:
		# v1 stored a single flat transmitter curve: {"expo":x,"rate":y}
		if d.get("tx") is Dictionary:
			var old: Dictionary = d["tx"]
			var prof := {"smoothing": 0.05}
			for ax in ["roll", "pitch", "yaw"]:
				prof[ax] = {"expo": SafeStore.number(old.get("expo"), 0.3, 0, 1), "rate": SafeStore.number(old.get("rate"), 1.0, 0, 2), "dz": 0.02, "trim": 0.0}
			d["transmitter"] = {"active_profile": "Migrated", "profiles": {"Migrated": prof}, "per_aircraft": {}}
			d.erase("tx")
		v = 2
	if v < 3:
		# v2 used "difficulty" for both assists and damage; v3 separates them.
		if d.has("gameplay") and typeof(d["gameplay"]) == TYPE_DICTIONARY:
			var g: Dictionary = d["gameplay"]
			if g.has("difficulty"):
				var diff := String(g["difficulty"])
				g["assist"] = {"easy": "arcade", "normal": "sport", "hard": "expert"}.get(diff, "sport")
				g.erase("difficulty")
		v = 3
	d["version"] = v
	return d

## Recursive merge: saved values override defaults only when types are compatible.
func deep_merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for k in over.keys():
		var ov = over[k]
		if out.has(k):
			var bv = out[k]
			if typeof(bv) == TYPE_DICTIONARY and typeof(ov) == TYPE_DICTIONARY:
				# free-form dictionaries (profiles, per-aircraft) are merged too
				out[k] = deep_merge(bv, ov)
			elif _compatible(bv, ov):
				out[k] = _coerce(bv, ov)
		else:
			out[k] = ov
	return out

func _compatible(a, b) -> bool:
	var ta := typeof(a)
	var tb := typeof(b)
	if ta == tb:
		return true
	var nums := [TYPE_INT, TYPE_FLOAT]
	return ta in nums and tb in nums

func _coerce(a, b):
	if typeof(a) == TYPE_INT and typeof(b) == TYPE_FLOAT:
		return int(b)
	if typeof(a) == TYPE_FLOAT and typeof(b) == TYPE_INT:
		return float(b)
	return b

func save() -> bool:
	if future_version:
		last_save_error = "Preferences belong to a newer app version; original preserved."
		save_failed.emit(last_save_error)
		return false
	data = validate(data)
	var result := SafeStore.write_json(SAVE_PATH, data)
	last_save_error = String(result.get("error", ""))
	if not result.get("ok", false):
		push_warning("Settings: " + last_save_error)
		save_failed.emit(last_save_error)
		return false
	return true

func validate(raw: Dictionary) -> Dictionary:
	var out := defaults()
	# Only accept known scalar fields. Free-form maps are validated separately.
	for section in ["controls", "graphics", "audio", "gameplay", "environment"]:
		var incoming: Variant = raw.get(section, {})
		if incoming is Dictionary:
			for key in out[section]:
				var base: Variant = out[section][key]
				var value: Variant = incoming.get(key, base)
				if base is bool and value is bool:
					out[section][key] = value
				elif base is String and value is String and value.length() < 80:
					out[section][key] = value
				elif (base is float or base is int) and (value is float or value is int) and is_finite(float(value)):
					out[section][key] = value
	for rule in [["controls","stick_size",0.6,1.6], ["controls","opacity",0.15,1.0],
		["graphics","render_scale",0.5,1.0], ["graphics","grass",0.0,2.0],
		["gameplay","aftermath",0.0,12.0], ["gameplay","slowmo",0.1,1.0]]:
		out[rule[0]][rule[1]] = clampf(float(out[rule[0]][rule[1]]), rule[2], rule[3])
	out["controls"]["mode"] = 1 if int(out["controls"]["mode"]) == 1 else 2
	out["graphics"]["fps"] = int(out["graphics"]["fps"]) if int(out["graphics"]["fps"]) in [0, 30, 60, 90, 120] else 60
	for key in out["audio"]:
		out["audio"][key] = clampf(float(out["audio"][key]), 0, 1)
	for rule in [["graphics","quality",["performance","high","ultra"],"high"],
		["gameplay","assist",["arcade","sport","expert"],"sport"],
		["gameplay","damage",["off","visual","physical"],"physical"],
		["gameplay","camera",["pilot","chase","locked","onboard","free"],"pilot"],
		["gameplay","units",["metric","imperial"],"metric"],
		["environment","time",["morning","midday","golden","overcast"],"golden"],
		["environment","wind",["calm","light","moderate","strong","gusty"],"light"],
		["environment","wind_dir",["headwind","crosswind_left","crosswind_right","quartering","tailwind"],"headwind"]]:
		out[rule[0]][rule[1]] = SafeStore.choice(out[rule[0]][rule[1]], rule[2], rule[3])
	var tx_raw: Variant = raw.get("transmitter", {})
	if tx_raw is Dictionary:
		var profiles: Variant = tx_raw.get("profiles", {})
		if profiles is Dictionary:
			var accepted := 0
			for key in profiles:
				if not key is String or key.is_empty() or key.length() > 64 or not profiles[key] is Dictionary:
					continue
				if accepted >= 64: break
				out["transmitter"]["profiles"][key] = validate_profile(profiles[key])
				accepted += 1
		var names: Array = out["transmitter"]["profiles"].keys()
		out["transmitter"]["active_profile"] = SafeStore.choice(tx_raw.get("active_profile"), names, "Balanced")
		var per: Variant = tx_raw.get("per_aircraft", {})
		if per is Dictionary:
			for key in per:
				if key is String and key.length() < 64 and per[key] in names and out["transmitter"]["per_aircraft"].size() < 64:
					out["transmitter"]["per_aircraft"][key] = per[key]
	var configs: Variant = raw.get("aircraft_cfg", {})
	if configs is Dictionary:
		for key in configs:
			if not key is String or key.length() > 64 or not configs[key] is Dictionary or out["aircraft_cfg"].size() >= 64: continue
			var c: Dictionary = configs[key]
			out["aircraft_cfg"][key] = {"battery": int(SafeStore.number(c.get("battery"),0,0,32)),
				"prop": int(SafeStore.number(c.get("prop"),0,0,32)), "engine": int(SafeStore.number(c.get("engine"),0,0,32)),
				"cg": SafeStore.number(c.get("cg"),0,-0.12,0.12), "fuel": SafeStore.number(c.get("fuel"),1,0.05,1),
				"throws": SafeStore.choice(c.get("throws"),["low","high"],"high")}
	var records: Variant = raw.get("records", {})
	if records is Dictionary:
		for key in records:
			if key is String and key.length() <= 128 and out["records"].size() < 256:
				var value := SafeStore.number(records[key], -1, -1, 36000)
				if value >= 0: out["records"][key] = value
	out["last_aircraft"] = raw.get("last_aircraft", "skylark") if raw.get("last_aircraft") is String else "skylark"
	out["last_mode"] = SafeStore.choice(raw.get("last_mode"),["free","landing","crosswind","engine_out","touchgo","aerobatic","gates","timetrial"],"free")
	return out

func validate_profile(raw: Dictionary) -> Dictionary:
	var profile := {"smoothing": SafeStore.number(raw.get("smoothing"),0.05,0,0.5)}
	for axis in ["roll","pitch","yaw"]:
		var d: Dictionary = raw[axis] if raw.get(axis) is Dictionary else {}
		profile[axis] = {"expo": SafeStore.number(d.get("expo"),0.3,0,1), "rate": SafeStore.number(d.get("rate"),1,0,2),
			"dz": SafeStore.number(d.get("dz"),0.02,0,0.5), "trim": SafeStore.number(d.get("trim"),0,-1,1)}
	return profile

func g(section: String, key: String, fallback = null):
	var s = data.get(section, {})
	if typeof(s) == TYPE_DICTIONARY and s.has(key):
		return s[key]
	var d: Dictionary = defaults().get(section, {})
	return d.get(key, fallback)

func s(section: String, key: String, value) -> void:
	if not data.has(section) or typeof(data[section]) != TYPE_DICTIONARY:
		data[section] = {}
	data[section][key] = value
	changed.emit(section)

# ---------------- transmitter profiles ----------------
func tx_profile_for(aircraft_id: String) -> Dictionary:
	var tx: Dictionary = data["transmitter"]
	var name := String(tx.get("active_profile", "Balanced"))
	var per: Dictionary = tx.get("per_aircraft", {})
	if per.has(aircraft_id) and tx["profiles"].has(per[aircraft_id]):
		name = per[aircraft_id]
	if not tx["profiles"].has(name):
		name = "Balanced"
		if not tx["profiles"].has(name):
			tx["profiles"][name] = TX_PRESETS["Balanced"].duplicate(true)
	return tx["profiles"][name]

func tx_profile_name_for(aircraft_id: String) -> String:
	var tx: Dictionary = data["transmitter"]
	var per: Dictionary = tx.get("per_aircraft", {})
	if per.has(aircraft_id) and tx["profiles"].has(per[aircraft_id]):
		return per[aircraft_id]
	return String(tx.get("active_profile", "Balanced"))

func aircraft_cfg(id: String) -> Dictionary:
	var all: Dictionary = data["aircraft_cfg"]
	if not all.has(id):
		all[id] = {"battery": 0, "prop": 0, "cg": 0.0, "throws": "high", "fuel": 1.0, "engine": 0}
	var c: Dictionary = all[id]
	for k in ["battery", "prop", "engine"]:
		if not c.has(k): c[k] = 0
	if not c.has("cg"): c["cg"] = 0.0
	if not c.has("throws"): c["throws"] = "high"
	if not c.has("fuel"): c["fuel"] = 1.0
	return c
