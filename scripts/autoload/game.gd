extends Node
## Global runtime state & constants shared by systems.

const VERSION := "1.0.0-beta.1"

# collision layers (bit values)
const L_WORLD := 1
const L_AIRCRAFT := 2
const L_DEBRIS := 4
const L_FOLIAGE := 8
const L_NPC := 16
const L_GATE := 32
const L_CHIP := 64

# surface ids
const SURF_GRASS := 0
const SURF_ASPHALT := 1
const SURF_DIRT := 2
const SURF_CONCRETE := 3
const SURF_WOOD := 4
const SURF_METAL := 5
const SURF_TALLGRASS := 6

const SURF_INFO := {
	0: {"mu": 0.62, "rr": 0.055, "name": "grass"},
	1: {"mu": 0.92, "rr": 0.014, "name": "asphalt"},
	2: {"mu": 0.60, "rr": 0.040, "name": "gravel"},
	3: {"mu": 0.85, "rr": 0.012, "name": "concrete"},
	4: {"mu": 0.55, "rr": 0.02, "name": "wood"},
	5: {"mu": 0.45, "rr": 0.015, "name": "metal"},
	6: {"mu": 0.55, "rr": 0.12, "name": "tall grass"},
}

var field: Node = null        # Field (world builder) instance
var wind: RefCounted = null   # Wind simulation
var fx: Node = null           # FX pools
var flight: Node = null       # Flight controller
var sim_time := 0.0
var rng := RandomNumberGenerator.new()
var headless := false

func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	rng.randomize()

func surface_at(p: Vector3) -> int:
	if field and field.has_method("surface_at"):
		return field.surface_at(p)
	return SURF_GRASS

func wind_at(p: Vector3) -> Vector3:
	if wind:
		return wind.sample(p)
	return Vector3.ZERO
