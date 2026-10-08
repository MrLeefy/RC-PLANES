# Work in progress (not in the build)

`mesh_kit_exact_paint_split.patch` is an unfinished change to `scripts/aircraft/mesh_kit.gd` that splits triangles exactly along livery boundaries instead of the AA lattice.

- Gains: sharp Viper 90 chevron edges and Tundra Cub stripes; about 40 % fewer LOD0 triangles.
- Known problem: a thin dark band on the Skipper fuselage gives a row of spikes, because an edge can cross a stripe that its endpoints do not have. The fix (halve such edges before the cut) was drafted but not applied or tested.
- Not in the shipped build. Apply with `git apply docs/wip/mesh_kit_exact_paint_split.patch`.
