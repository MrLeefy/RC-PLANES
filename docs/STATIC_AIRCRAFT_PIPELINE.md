# Static aircraft runtime pipeline

RC Park is moving away from runtime procedural aircraft geometry.

## Shipping rule

The production APK should load authored/pre-baked aircraft resources:

```
high-detail source (Blender / GLB)
        |
        +-- offline validation
        +-- separated control surfaces
        +-- LOD generation
        +-- RCBeam deformation cage
        +-- simplified collision proxies
        v
Godot imported/static resources
        |
        v
PackedScene / imported GLB in APK
```

No player-facing aircraft should need to generate its render mesh vertex-by-vertex in GDScript at runtime.

## Legacy aircraft transition

The original 16 aircraft remain useful as physics/aerodynamic references. Their current procedural visual builder is retained as an **offline baker and safe fallback** while the static fleet is produced.

`tools/bake_legacy_aircraft.gd` converts a legacy aircraft into:

- `assets/aircraft_baked/<id>.scn` — compressed binary PackedScene containing the built visual hierarchy and LOD meshes.
- `assets/aircraft_baked/<id>.res` — compressed binary physics/animation blueprint containing component, panel, surface, engine, wheel and collision data plus NodePaths back into the scene.

At runtime `AircraftBakedLibrary` reconstructs the live references from NodePaths. When an exact baked resource is present, `Aircraft.setup()` does **not instantiate AircraftBuilder at all**.

All 16 default-detail models now ship saved scene/blueprint pairs. Workshop battery, propeller, fuel, CG and throws use a data-only configuration layer. Gear assemblies and collision data translate with CG to preserve the legacy ballast solution; no mesh generation is needed. Missing assets or non-default detail levels retain the procedural fallback.

These are the original stylized RC designs saved as premade resources, not exact real-aircraft replicas or newly authored high-detail models. The baseline geometry is fixed independently of the small RCBeam cage. Cage deformation updates render component transforms and aerodynamic panel positions/normals/area; attachment fracture removes lift and control authority on the parent.

`assets/aircraft_baked/baseline.json` locks the 16 scene/blueprint file hashes. `python tools/lock_aircraft_baseline.py` checks them. Intentional offline revisions require visual/physics validation followed by `--write`; runtime never writes the baseline.

Skyliner 74 and Cargomaster 130 have an offline nose/flight-deck revision authored in `assets/aircraft_art/transport_noses.json`. `tools/refine_transport_noses.gd` edits the immutable legacy scene inputs, recalculates normals/LODs and saves the revised premade scenes. Their physics `.res` files are unchanged. Set `cfg.legacy_model=true` to load the preserved original scenes from `assets/aircraft_legacy/`. When rebuilding everything, run the legacy baker, then the nose-refinement tool, then validate and explicitly lock the accepted baseline.

## Measured proof of concept

On the Oracle Linux build host using Godot 4.7.2, default-detail Skylark:

- procedural `AircraftBuilder.build()`: **4948.286 ms**
- baked PackedScene + blueprint load: **42.023 ms**
- observed speedup: **117.8x**
- structure count comparison: exact (24 components, 13 panels, 9 control surfaces, 1 engine, 3 wheels)
- compressed Skylark files: ~894 KB scene + ~9.8 KB blueprint

These numbers are build-host measurements, not an Android device claim. Android profiling remains required.

After the Workshop gear-data fix and transport artwork revision, a local Windows Godot 4.7.2 headless benchmark across all 16 models measured **14,792.477 ms** total procedural construction versus **116.247 ms** total saved-scene/blueprint instantiation (**127.3x**). This measures the loader/build comparison, not complete Aircraft setup or Android frame time. All component/panel/control/engine/wheel counts matched.

## Realistic replacement model requirements

A replacement aircraft should arrive as an authored high-detail master, not generated runtime geometry.

Required where applicable:

- physically plausible dimensions and proportions
- PBR materials and texture maps
- separate ailerons, flaps, elevator, rudder, prop/fan and gear
- sensible object pivots at hinge/rotation axes
- clean UVs/normals/tangents
- LOD0..LOD3
- simplified collision proxy meshes
- RCBeam node-cage authoring data
- detachable structural groups (wing panels, nose/firewall, tail, gear, canopy)
- verified commercial redistribution license

Target rendering topology is independent of structural physics. A 100k–300k-triangle close-up mesh may still use only tens to low hundreds of RCBeam nodes.

## Performance intent

Runtime CPU budget should be spent on:

1. flight/aerodynamic simulation,
2. RCBeam structural solving during impacts,
3. world collision / Jolt,
4. replay and camera,

not on regenerating static art.

The legacy builder remains useful for regression/debug visualization and for generating reference geometry offline, but it is not the long-term shipping renderer.
