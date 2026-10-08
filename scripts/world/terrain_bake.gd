class_name TerrainBake
extends RefCounted
## One-off GPU bake of the ground colour, so the terrain shader can read textures instead of evaluating
## about ten noise lookups per pixel. Two textures: a fine one over the flying field and pits, and a coarse
## one over the whole terrain (farmland, hedges, forest). Plus a small tiling noise texture for the blade
## and clump detail. Falls back to the procedural shader when there is no GPU (headless runs).

const NEAR := Rect2(-256.0, -128.0, 512.0, 256.0)   # world x, z of the corner, size (m)
const NEAR_PX := Vector2i(2048, 1024)                # 0.25 m per texel
const FAR := Rect2(-1200.0, -1200.0, 2400.0, 2400.0)
const FAR_PX := Vector2i(1024, 1024)                 # 2.3 m per texel
const DETAIL_PX := 128

## RC_NOBAKE=1 forces the procedural ground shader (for A/B comparisons).
static func available() -> bool:
	return DisplayServer.get_name() != "headless" and RenderingServer.get_rendering_device() != null \
		and OS.get_environment("RC_NOBAKE") != "1"

## Returns {"near", "far", "detail"} textures, or an empty dictionary when baking is not possible.
static func bake(host: Node) -> Dictionary:
	if not available():
		return {}
	var near := await _render(host, NEAR, NEAR_PX)
	var far := await _render(host, FAR, FAR_PX)
	if near == null or far == null:
		return {}
	return {"near": near, "far": far, "detail": detail_texture()}

static func _render(host: Node, rect: Rect2, px: Vector2i) -> ImageTexture:
	return await render_shader(host, "res://shaders/terrain_bake.gdshader", {"rect": Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y)}, px)

## Cloud noise for the sky shader (r: 4-octave fbm, g: fine breakup), tileable. Null without a GPU.
static func sky_noise(host: Node) -> ImageTexture:
	if not available():
		return null
	return await render_shader(host, "res://shaders/sky_noise_bake.gdshader", {}, Vector2i(512, 512))

## Renders a canvas_item shader once into an RGBA8 texture with mipmaps.
static func render_shader(host: Node, shader_path: String, params: Dictionary, px: Vector2i) -> ImageTexture:
	var vp := SubViewport.new()
	vp.size = px
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cr := ColorRect.new()
	cr.size = Vector2(px)
	var mat := ShaderMaterial.new()
	mat.shader = load(shader_path)
	for k in params:
		mat.set_shader_parameter(k, params[k])
	cr.material = mat
	vp.add_child(cr)
	host.add_child(vp)
	for _i in 3:
		await host.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return null
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

## Tileable value-noise tile. r: blade streaks, g: clumps, b: grain. The shader samples it at two scales
## (about 46 and 1.4 cycles per metre), see terrain_baked.gdshader.
static func detail_texture() -> ImageTexture:
	var bands := [
		[[32, 0.55], [64, 0.45]],   # r
		[[8, 0.6], [24, 0.4]],      # g
		[[16, 1.0]],                # b
	]
	var n := DETAIL_PX * DETAIL_PX
	var chans: Array = []
	var seed_i := 7
	for band in bands:
		var acc := PackedFloat32Array()
		acc.resize(n)
		for octave in band:
			var noise := FastNoiseLite.new()
			noise.noise_type = FastNoiseLite.TYPE_VALUE
			noise.seed = seed_i
			seed_i += 13
			noise.frequency = float(octave[0]) / float(DETAIL_PX)
			var data := noise.get_seamless_image(DETAIL_PX, DETAIL_PX, false, false).get_data()
			var w := float(octave[1]) / 255.0
			for i in n:
				acc[i] += float(data[i]) * w
		chans.append(acc)
	var out := PackedByteArray()
	out.resize(n * 3)
	for i in n:
		out[i * 3] = clampi(roundi(float(chans[0][i]) * 255.0), 0, 255)
		out[i * 3 + 1] = clampi(roundi(float(chans[1][i]) * 255.0), 0, 255)
		out[i * 3 + 2] = clampi(roundi(float(chans[2][i]) * 255.0), 0, 255)
	var im := Image.create_from_data(DETAIL_PX, DETAIL_PX, false, Image.FORMAT_RGB8, out)
	im.generate_mipmaps()
	return ImageTexture.create_from_image(im)
