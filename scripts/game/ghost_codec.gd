class_name GhostCodec
extends RefCounted
## Validated, bounded, setup-specific ghost tracks. Never index untrusted rows.
const VERSION := 2
const MAX_SAMPLES := 12001
const MAX_SECONDS := 600.0

static func decode(data: Dictionary, setup_key: String) -> Dictionary:
	if data.get("version") != VERSION or data.get("setup") != setup_key:
		return {"ok": false, "error": "incompatible ghost"}
	var best := SafeStore.number(data.get("best"), -1, -1, MAX_SECONDS + 1)
	var rows: Variant = data.get("track")
	if best <= 0 or not rows is Array or rows.size() < 2 or rows.size() > MAX_SAMPLES:
		return {"ok": false, "error": "invalid ghost header or sample count"}
	var previous := -1.0
	var track := []
	for row in rows:
		if not row is Array or row.size() != 8:
			return {"ok": false, "error": "invalid ghost row length"}
		for value in row:
			if not (value is int or value is float) or not is_finite(float(value)):
				return {"ok": false, "error": "non-finite or non-numeric ghost field"}
		var t := float(row[0])
		if t <= previous or t < 0.0 or t > MAX_SECONDS or t > best + 0.1:
			return {"ok": false, "error": "invalid ghost time order/range"}
		var pos := Vector3(row[1], row[2], row[3])
		if pos.length() > 10000.0:
			return {"ok": false, "error": "ghost position out of bounds"}
		var q := Quaternion(row[4], row[5], row[6], row[7])
		if q.length_squared() < 0.5 or q.length_squared() > 1.5:
			return {"ok": false, "error": "invalid ghost rotation"}
		track.append([t, Transform3D(Basis(q.normalized()), pos)])
		previous = t
	if float(rows[0][0]) > 0.1 or best - previous > 0.2:
		return {"ok": false, "error": "incomplete ghost track"}
	return {"ok": true, "best": best, "track": track}

static func encode(track: Array, setup_key: String, best: float) -> Dictionary:
	var rows := []
	for sample in track:
		var xf: Transform3D = sample[1]
		var q := xf.basis.get_rotation_quaternion().normalized()
		rows.append([sample[0], xf.origin.x, xf.origin.y, xf.origin.z, q.x, q.y, q.z, q.w])
	return {"version": VERSION, "setup": setup_key, "best": best, "track": rows}

static func index_at(track: Array, t: float) -> int:
	var low := 0
	var high := track.size() - 1
	while low < high:
		var mid := (low + high + 1) / 2
		if float(track[mid][0]) <= t: low = mid
		else: high = mid - 1
	return low