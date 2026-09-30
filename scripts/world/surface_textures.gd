class_name SurfaceTextures
extends RefCounted
## Shared, seamless, mipmapped surface maps generated once per launch. They are
## sampled with anisotropic mip filtering, not unfiltered screen-frequency dots.
static var aggregate: NoiseTexture2D
static var aggregate_normal: NoiseTexture2D

static func initialize() -> void:
	if aggregate != null: return
	var noise := FastNoiseLite.new()
	noise.seed = 7193
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	noise.cellular_return_type = FastNoiseLite.RETURN_DISTANCE
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.frequency = 0.29
	aggregate = NoiseTexture2D.new()
	aggregate.width = 512
	aggregate.height = 512
	aggregate.seamless = true
	aggregate.generate_mipmaps = true
	aggregate.noise = noise
	aggregate_normal = NoiseTexture2D.new()
	aggregate_normal.width = 512
	aggregate_normal.height = 512
	aggregate_normal.seamless = true
	aggregate_normal.generate_mipmaps = true
	aggregate_normal.as_normal_map = true
	aggregate_normal.bump_strength = 1.1
	aggregate_normal.noise = noise

static func wait_ready() -> void:
	initialize()
	if aggregate.get_image() == null: await aggregate.changed
	if aggregate_normal.get_image() == null: await aggregate_normal.changed
