# Visual upgrade pass (0.10.1)

Build fixes
- Fixed two GDScript type-inference errors that stopped `AircraftBuilder` and `TouchButton` from compiling on Godot 4.7.2
  (the aircraft never spawned): `for side: float in [...]` in `_fracture_pair`, explicit `Vector2` in `touch_button.gd`.

Aircraft
- Livery edges: fuselage/wing lofts are denser at LOD0, and `MeshKit` now re-paints triangles that straddle a paint edge
  (barycentric lattice, K=4, exact on the parent triangle so no cracks). Stripes, sunbursts, chevrons and camo are crisp
  instead of smeared. LOD1/LOD2 index lists are untouched. `tests/tri_count.gd` prints the LOD0 triangle budget (~0.84 M total
  over 16 aircraft, ~30-95 k each).
- Paint albedo is capped at real white-paint reflectance (0.86) so white airframes keep their form in direct sun.
- Polished-metal finish is less mirror-like (no more blown-out specular streak on the warbird).
- Decals are sampled against the skin over their full length and height, pushed clear of it and yawed to follow it, so text
  is never clipped mid-word; glyph resolution raised.
- Camo is smooth two-tone splinter instead of hashed blocks.
- Turbofan nacelles have a rounded inlet lip, barrel and exhaust taper; pylons are swept lens-section lofts.
  The SST box intakes are rounded superellipse lofts.
- Biplane (Skipper): interplane struts, cabane struts and flying wires (they were missing; the wings floated).
- Wheel pants are slimmer and more streamlined; glow-engine cylinder heads are dark anodised instead of a bright disc.

World
- Trees: 512 px leaf atlas with soft edges, back-to-front leaf shading, alpha-to-coverage, baked canopy occlusion.
- Lawn: blade-scale and clump detail in `terrain.gdshader` (faded out when sub-pixel).
- Runway: marking AA width is clamped (no more smeared paint at grazing angles); runway numerals rendered at proper glyph size.
- People: rebuilt with torso/neck/head/hair/ears, caps, sleeves, belts, shoes and hands.

Screenshot QA on a headless box: install `mesa-vulkan-drivers`, then
`VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a godot --path . --rendering-driver vulkan res://tests/shots.tscn -- <plan>`.
