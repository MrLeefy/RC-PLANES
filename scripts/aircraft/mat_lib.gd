class_name MatLib
extends RefCounted
## Shared material cache. Every aircraft of the same construction shares one
## material (liveries come from vertex colours), keeping draw state changes and
## shader variants minimal on mobile.

static var _cache: Dictionary = {}
static var _shaders: Dictionary = {}

const KIND := {"foam": 0, "film": 1, "composite": 2, "carbon": 3, "metal": 4, "fabric": 5,
	"rubber": 6, "plastic": 7, "painted": 8, "cockpit": 9}
const SUBSTRATE := {
	"foam": Color(0.92, 0.92, 0.88), "film": Color(0.78, 0.64, 0.42), "composite": Color(0.62, 0.62, 0.58),
	"carbon": Color(0.2, 0.2, 0.2), "metal": Color(0.85, 0.86, 0.88), "fabric": Color(0.75, 0.62, 0.42),
	"rubber": Color(0.1, 0.1, 0.1), "plastic": Color(0.7, 0.7, 0.7), "painted": Color(0.62, 0.63, 0.63),
	"cockpit": Color(0.1, 0.1, 0.1),
}

static func shader(path: String) -> Shader:
	if not _shaders.has(path):
		_shaders[path] = load(path)
	return _shaders[path]

static func aircraft(kind: String) -> ShaderMaterial:
	var key := "ac_" + kind
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = shader("res://shaders/aircraft.gdshader")
	m.set_shader_parameter("kind", KIND.get(kind, 7))
	var rough := 0.5
	var coat := 0.0
	var bump := 0.25
	var lines := 0.0
	match kind:
		"foam": rough = 0.69; bump = 0.12
		"film": rough = 0.31; coat = 0.42; bump = 0.10
		"composite": rough = 0.30; coat = 0.55; lines = 0.5
		"carbon": rough = 0.3; coat = 0.6
		"metal": rough = 0.25; lines = 0.8
		"fabric": rough = 0.62
		"rubber": rough = 0.92
		"plastic": rough = 0.45
		"painted": rough = 0.55; lines = 0.55
		"cockpit": rough = 0.8
	m.set_shader_parameter("rough", rough)
	m.set_shader_parameter("coat", coat)
	m.set_shader_parameter("bump", bump)
	m.set_shader_parameter("panel_lines", lines)
	m.set_shader_parameter("substrate", SUBSTRATE.get(kind, Color(0.7, 0.7, 0.7)))
	_cache[key] = m
	return m

static func glass(tint: Color, opacity := 0.62) -> ShaderMaterial:
	var key := "glass_%s_%.2f" % [tint.to_html(), opacity]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = shader("res://shaders/glass.gdshader")
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("opacity", opacity)
	m.render_priority = 1
	_cache[key] = m
	return m

static func prop_disc(blade: Color, tip: Color, tip_band: float, blades: int) -> ShaderMaterial:
	var key := "disc_%s_%s_%.2f_%d" % [blade.to_html(), tip.to_html(), tip_band, blades]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = shader("res://shaders/prop_disc.gdshader")
	m.set_shader_parameter("blade_color", blade)
	m.set_shader_parameter("tip_color", tip)
	m.set_shader_parameter("tip_band", tip_band)
	m.set_shader_parameter("blades", float(blades))
	m.render_priority = 2
	_cache[key] = m
	return m

static func chip() -> ShaderMaterial:
	if _cache.has("chip"):
		return _cache["chip"]
	var m := ShaderMaterial.new()
	m.shader = shader("res://shaders/debris_chip.gdshader")
	_cache["chip"] = m
	return m

static func emissive(c: Color, energy := 2.0) -> StandardMaterial3D:
	var key := "em_" + c.to_html()
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.roughness = 0.3
	_cache[key] = m
	return m

static func ghost() -> StandardMaterial3D:
	if _cache.has("ghost"):
		return _cache["ghost"]
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.4, 0.8, 1.0, 0.28)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_BACK
	m.no_depth_test = false
	_cache["ghost"] = m
	return m

static func simple(c: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var key := "simple_%s_%.2f_%.2f" % [c.to_html(), rough, metal]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	_cache[key] = m
	return m

static func vcol(rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var key := "vcol_%.2f_%.2f" % [rough, metal]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = false
	m.roughness = rough
	m.metallic = metal
	_cache[key] = m
	return m

static func all_cached() -> Array:
	return _cache.values()
