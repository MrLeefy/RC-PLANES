class_name SafeStore
extends RefCounted
## Bounded JSON I/O with checked replacement and last-known-good recovery.
## Never delete the primary before a validated replacement and backup exist.

const MAX_BYTES := 4 * 1024 * 1024

static func read_json(path: String, max_bytes := MAX_BYTES) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "open: " + error_string(FileAccess.get_open_error())}
	if f.get_length() > max_bytes:
		f.close()
		return {"ok": false, "error": "file exceeds size limit"}
	var text := f.get_as_text()
	var err := f.get_error()
	f.close()
	if err != OK and err != ERR_FILE_EOF:
		return {"ok": false, "error": "read: " + error_string(err)}
	var parser := JSON.new()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return {"ok": false, "error": "invalid JSON object"}
	return {"ok": true, "data": parser.data, "text": text}

static func write_json(path: String, data: Dictionary) -> Dictionary:
	var text := JSON.stringify(data, "  ")
	if text.to_utf8_buffer().size() > MAX_BYTES:
		return {"ok": false, "error": "save exceeds size limit"}
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "error": "write: " + error_string(FileAccess.get_open_error())}
	f.store_string(text)
	f.flush()
	var err := f.get_error()
	f.close()
	if err != OK:
		return {"ok": false, "error": "flush: " + error_string(err)}
	var check := read_json(tmp)
	if not check.get("ok", false) or check.get("text", "") != text:
		return {"ok": false, "error": "temporary save verification failed"}
	# Backup only a valid primary; a corrupt primary must not replace a good .bak.
	if read_json(path).get("ok", false):
		err = DirAccess.copy_absolute(path, path + ".bak.tmp")
		if err != OK or not read_json(path + ".bak.tmp").get("ok", false):
			return {"ok": false, "error": "backup creation failed: " + error_string(err)}
		err = DirAccess.rename_absolute(path + ".bak.tmp", path + ".bak")
		if err != OK:
			return {"ok": false, "error": "backup replacement failed: " + error_string(err)}
	# Godot's rename performs replacement on the supported Android/Linux paths.
	# On failure keep both the original and the recoverable .tmp; no delete fallback.
	err = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		return {"ok": false, "error": "replacement failed: " + error_string(err)}
	if not read_json(path).get("ok", false):
		return {"ok": false, "error": "completed save could not be read"}
	return {"ok": true, "path": ProjectSettings.globalize_path(path), "text": text}

static func number(value: Variant, fallback: float, low: float, high: float) -> float:
	if (value is float or value is int) and is_finite(float(value)):
		return clampf(float(value), low, high)
	return fallback

static func choice(value: Variant, allowed: Array, fallback: String) -> String:
	return String(value) if value is String and value in allowed else fallback
