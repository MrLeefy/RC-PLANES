class_name FoliageIndex
extends RefCounted
## Analytic canopy broad phase. No scene nodes are activated as the plane moves,
## so crossing a spatial bucket cannot create a collision-free activation frame.
const CELL_SIZE := 48.0
var buckets: Dictionary = {}
var max_radius := 0.0
var count := 0

func add(center: Vector3, radius: float, density: float) -> void:
	if radius <= 0.0 or density <= 0.0:
		return
	var key := Vector2i(floori(center.x / CELL_SIZE), floori(center.z / CELL_SIZE))
	if not buckets.has(key):
		buckets[key] = []
	buckets[key].append({"center": center, "radius": radius, "density": density})
	max_radius = maxf(max_radius, radius)
	count += 1

func query(center: Vector3, aircraft_radius: float, out: Array) -> void:
	out.clear()
	var reach := maxf(aircraft_radius, 0.0) + max_radius
	var lo := Vector2i(floori((center.x - reach) / CELL_SIZE), floori((center.z - reach) / CELL_SIZE))
	var hi := Vector2i(floori((center.x + reach) / CELL_SIZE), floori((center.z + reach) / CELL_SIZE))
	for z in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var key := Vector2i(x, z)
			if not buckets.has(key):
				continue
			for item in buckets[key]:
				var radius := aircraft_radius + float(item["radius"])
				if center.distance_squared_to(item["center"]) < radius * radius:
					out.append(item)
