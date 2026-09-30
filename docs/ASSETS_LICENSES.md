# Assets & licenses

## Third-party content shipped in the APK
- **Godot Engine 4.7.2** runtime (MIT license, © Juan Linietsky, Ariel Manzur and contributors) — include the Godot license text in your store listing / about screen (the in-game About tab credits it).
- **Jolt Physics** (bundled with Godot, MIT license).
- No other third-party assets.

## Original / procedural content (this project)
| Asset | Source |
|---|---|
| All 16 aircraft meshes, liveries, labels | Generated in code (`aircraft_builder.gd`, `mesh_kit.gd`) from original data |
| Terrain, runway, fences, buildings, props, parked aircraft | Generated in code (`field.gd`) |
| Trees, bushes, leaf textures | Generated in code (`tree_lib.gd`) |
| Materials / textures (asphalt, grass, bark, chain-link, sky, clouds) | Procedural shaders in `shaders/` |
| All sound effects and engine sounds | Synthesized at first launch (`sfx.gd`), cached to user storage |
| App icon & adaptive icon layers | Generated with a Python/PIL script (original plane silhouette) |
| UI | Godot controls, default font |

No commercial RC models, textures, sounds, logos, or trademarked names were downloaded or used. Aircraft are original designs "in the style of" common RC categories.