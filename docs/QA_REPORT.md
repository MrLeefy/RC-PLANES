# QA / test report

Date: 2026-09-26 · Build: 0.9.0 (versionCode 9) · Godot 4.7.2 stable · Jolt · 120 Hz physics

## Test environment (important)
- All tests were run on a **Linux x86-64 cloud container**: headless Godot for physics/logic tests, and the Vulkan **software rasterizer (lavapipe)** under Xvfb for screenshots.
- **Nothing has been run on a physical Android device.** The APKs were built, zip-aligned, signed and verified (`apksigner verify`), but never installed or launched on a phone. No Android frame rate, thermal, memory, touch-latency or audio-latency figure has been measured.

## Realism pass (2026-10-04): `-- --upgrade-test` 247 / 247 PASS
- Run with `godot --headless --fixed-fps 120 --path . -- --upgrade-test` (the same suite also runs in real time, just slowly). `tests/realism_tests.gd` adds, for **each of the 16 aircraft**: rest on gear / prop clearance, control polarity and surface following, retracts and flaps, take-off, stall, spin and recovery, hands-off cruise, ordinary landing and roll-out, damage and repair; plus spec envelopes, mass book-keeping, audio family spectra, and fuel/detached-part mass effects.
- `tests/flight_test.tscn` completes without errors for all 16 aircraft (printing bench, not pass/fail). It still reports small spawn-drop damage at rest for Cargomaster (0.19) and Skyliner (0.34); the asserted rest test places them without damage.
- Fixes found by the suite: Mach Arrow could not rotate (wing incidence 3 deg, mains moved forward, larger elevon chord/throw); Valor wing-drop at stall (washout 2.5 deg); test-harness state leaking from the base suites (wind, per-aircraft config) now reset.
- Rendering: turntable views of all 16 aircraft (three-quarter and gear-up) rendered under lavapipe and inspected; no new defects found in the views checked (Mach Arrow, Valor looked at closely, others at thumbnail level).
- APK: `build/RCPark-debug.apk` re-exported and signed with apksigner (28.99 MB). Not installed on a device.
- Not measured here: Android frame rate, thermals, audio latency, touch feel. Software-rendered screenshots only.

### Follow-up (2026-10-05)
- `-- --upgrade-test` 248 / 248 (two consecutive runs); `tests/flight_test.tscn` clean.
- Airliner flight-deck glazing, C-130 / 747 / Super Cub proportions (length/span test against published dimensions), 747 wing-body belly fairing, C-130 rear ramp and paratroop-door seams.
- Camera: chase/orbit distances already scale with span and length and use a ray plus a sphere sweep for collision avoidance; no change needed.
- Aspect-ratio QA (lavapipe, game booted, Skyliner on the runway): 2400x1080 (20:9), 1920x1200 (16:10) and 1600x1200 (4:3). HUD, side buttons and both sticks stay on screen and clear of the edges. Simulated notch/cutout insets were not tested.
- Vortex 540 and Tiger 28 bodies shortened to class proportions; golden-hour fog lightened (0.0016 to 0.0012). Midday and golden-hour renders inspected (lavapipe).
- Mach Arrow droop nose, Skyliner exhaust core plugs and thinner pylons (rendered and inspected). New test: HUD buttons stay inside simulated cutouts at 2400x1080 (side and top/bottom insets), 1920x1200, 1600x1200 and 2960x1344 (249 / 249).
- Runway shader already models rubber, patches, cracks and edge wear; not changed.
- Mach Arrow now has a curved ogival wing leading edge (new `ogive` wing option, straight trailing edge). Default-quality grass instances raised 50 % (ultra 2.2x), software-render primitive count in the flight view rose from about 303k to 393k; no device frame-rate measured. Stall test now treats a steady mush that reaches the ground as the "mushed" outcome.
- Sky: added a thin high cirrus layer (checked looking up at midday; subtle, no artefacts). Terrain shader already has farmland patches, mowing stripes, hedges, wear and gravel, so it was not changed.
- Terrain: drifting cloud shadows (soft patches moving with the sky clouds, scaled by cloud cover), checked in a midday aerial render.
- APK static checks (apksigner / aapt2): signature verifies with v2 and v3 schemes, package com.rcpark.sim.upgrade versionCode 10, target SDK 36, arm64-v8a native libraries only, Vulkan feature declared, 28.99 MB. This is a static check only; the APK has not been installed.
- Device testing: the cloud environment has no KVM, emulator or system images, so no Android run was possible.
- Not done: device testing; notch/cutout inset tests.

### Model realism pass (2026-10-05, after on-phone feedback "models look like trash")
- Viper 90: cheek intakes are now lofted ducts that fade into the fuselage instead of ellipsoid pods stuck on the side.
- Airliner/cargo noses: oversized black radome caps reduced to a small tip; Skyliner nose reshaped (longer, tapered, drooped).
- Skyliner: larger passenger windows, door outlines, flap-track canoe fairings, belly fairing; composite skins now carry panel seams and rivets (shader).
- Cargomaster: rear ramp outline and paratroop-door seams; gear sponsons against the fuselage.
- Striker 16: leading-edge root extensions (LERX) that blend into the wing leading edge.
- Wheel spats are teardrops sized to the wheel instead of balloons.
- Tried a second paint-edge refinement level: doubled triangles for a marginal gain, reverted.
- Still rough: stair-stepped livery stripe edges on some fuselages (vertex-colour paint), blurry decals at close range, simple pilot figures, no cockpit interiors beyond a pilot and tub.

### Reference-photo pass, menu performance (2026-10-06)
- Hangar lag: model building (about 0.4 to 2.1 s per aircraft, all on the main thread) now runs on a worker thread; the main thread needs about 1 ms to attach the result. Up to 6 models stay cached and the neighbouring cards are pre-built, so flipping through the carousel is instant after the first build. Display models skip flight trim and impact probes. Measured headless: skylark 1.0 s, vortex540 2.1 s, skyliner 1.1 s on the worker; main thread stays at 150 to 300 frames during the build.
- Carousel drag: cards no longer take the pointer, so a drag that ends over a card scrolls instead of selecting it; taps (under 18 px movement, under 0.7 s) select. New test covers tap, drag and long-hold.
- Shader: aircraft skin now has bevelled panel-seam normals, rivet domes, brushed-metal streaking, orange-peel paint, airflow-aligned grime and soot, underside soiling, and edge sheen on foam/film/fabric, all gated by a graphics-quality global (off on Performance, on for High, stronger on Ultra); glass has faint scratches and uneven tint.
- Real reference images (Wikimedia Commons, used only as study material, not shipped): 747-400, C-130 (3-view and photo), Concorde, P-51D (3-view, side, front), F-16 (3-view, profile), A-10 (3-view, photo). Cargomaster now has C-130 style main-gear sponsons, deeper boxy fuselage and underwing tanks.
- Belle 51 (P-51D reference): boxy belly radiator scoop with dark inlet, chin carburettor scoop, dorsal fillet. Striker 16 (F-16 reference): dorsal spine added. Checked against the P-51D three-view (length/span 0.87), F-16 and A-10 three-views and photos.
- Not yet done from the photos: re-modelling the P-51, F-16, A-10, Concorde and 747 outlines against the 3-views (only the C-130 was reworked this round), and no texture photos are used.

### Reference pass 2 (2026-10-06) - what was and was not matched
- Fetched into the scratchpad (study only, never shipped): photo + three-view for 747-400, C-130, Concorde, P-51D, F-16, A-10, F-22, Cessna 150, Super Cub.
- Matched/measured: new test "scale: aspect ratio ... within 12 %" against published span and wing area for all nine real types; length/span within 8 %. Fixed Striker (wing 1.70 m span), Skyliner and Cargomaster wing areas; Super Cub fuselage slimmed, round tips; Skylark wing seated lower with smaller spats.
- New test "hangar: display models build off-thread, are cached, neighbours are prefetched and a cached switch is instant" (main thread kept rendering 4400+ frames during the build; cached switch instant). 252-ish tests, all passing on two runs.
- NOT matched: F-22 chined nose and canted-tail details, Concorde nacelle pairs and wing kink, 747 upper-deck window rows and nacelle shapes, A-10 twin-fin tail shape. These were compared by eye only; no measured outline fit was done.
- NOT fixed: stair-stepped livery stripe edges. Raising the fuselage row count 110 to 190 (+27 % triangles) and ring segments made no visible difference, because the steps come from the per-vertex paint function itself; a shader-side stripe mask would be needed. Decals are still blurry up close.
- Needs the user's phone: frame rate, thermals, touch feel, audio latency.

### Reference pass 3 (2026-10-06): livery edges
- Root cause of the stair-stepped / dashed stripes: (a) thin bands narrower than a triangle between three identically coloured corners vanished (dashed stripe); (b) the paint-edge lattice was too coarse (K=4).
- Fix: refinement now also probes the centroid and edge midpoints, and the lattice is K=6 on High/Ultra (K=4 on Performance, via `MeshKit.refine_k` set from the graphics quality). Stripes on Skylark, Cub and Belle 51 now render continuous and crisp in turntable renders. The Super Cub's zig-zag stripe was replaced by a straight cheat line plus pinstripe (the real Cub has none).
- Cost (measured with tests/tri_count.gd): fleet total 853k -> 1.43M triangles (+68 %), per aircraft about 52k -> 90k (Skylark). This is OVER the 15 % budget I set; only one aircraft is on screen at a time, but the cost on a real phone is unmeasured.
- Decals: Label3D now 256 px with alpha-to-coverage and opaque prepass (crisper edges); not verified up close on a device.
- 747: second window row along the upper-deck hump. New test "scale: A-10 twin fins, F-22 twin canted fins, Concorde/747/C-130 four engines, F-16 single fin and engine".
- Still NOT matched to references: F-22 chined nose, Concorde wing kink and nacelle shape, 747 engine/pylon shape, A-10 tail shape (compared by eye; no measured outline fit).
- 253 / 253 tests on two consecutive runs; flight bench clean; import clean.

### Reference pass 4 (2026-10-06): measured outline fit and triangle budget
- New dev tool `tools/outline_fit/` (reference images are NOT in the repo): flood-fills the top view of each real type's three-view into a silhouette, rasterises the replica's planform (fuselage, wings, tailplane, nacelles) at the same normalised length/span, and reports silhouette IoU. Bounded random search on wing/tailplane z, chord and sweep (max +-15 %) gave large gains.
- IoU before -> after (applied): Skylark 0.77 -> 0.89, Specter 22 (F-22) 0.65 -> 0.81, Brute 10 (A-10) 0.72 -> 0.86, Skyliner (747) 0.79 -> 0.88, Striker 16 (F-16, wing only) 0.54 -> about 0.7.
- Found but NOT applied, because the fitted geometry broke flight tests (no test was loosened): Tundra Cub (0.68; hidden-lead ballast 6 %), Belle 51 (0.69; spin-resistance test), Cargomaster (0.70; gear rest test), Mach Arrow (0.70; take-off test), and the Striker tailplane (spin must-enter test). These need joint retuning of CG/gear with the new wing, which I did not do.
- Triangle budget: livery quality tiers (Performance lean / High default / Ultra dense). Default High measures 991k triangles fleet-wide vs 853k originally (+16 %), Skylark 59k vs 52k. Performance is leaner than the original; Ultra is the +68 % variant.
- Remaining mismatches (judged by eye only): F-22 chined nose, Concorde wing kink/nacelle shape, 747 engine/pylon shape, A-10 tail shape. Fuselage outlines were not fitted, only wing/tailplane planforms.

### Reference pass 5 (2026-10-06): outline fits applied and locked in by a test
- Applied the fitted wing planforms to all nine real types except the Striker tailplane (its must-enter-spin test failed with the fitted tail; the test was not loosened). Retuned to keep flight tests green: Tundra Cub CG 0.375 (was 0.34; note this is aft for a Cub and sits just inside the 20-38 % envelope), Cargomaster main gear z 0.84 and sponsons shifted, Mach Arrow main gear z 1.18, Belle 51 washout 3.5 deg.
- Planform silhouette overlap (IoU) vs the real three-view top view, now: Skylark 0.86, Tundra Cub 0.87, Belle 51 0.74, Specter 22 0.80, Brute 10 0.84, Striker 16 0.73, Mach Arrow 0.77, Skyliner 0.85, Cargomaster 0.81 (40x40 grid; earlier 240x240 numbers differ slightly).
- New test "scale: planform outline overlaps the real type's three-view silhouette (IoU floors)" using derived occupancy grids in tests/reference_outlines.json (data derived from the drawings; no image shipped). Floors sit about 0.04 under the measured values.
- 254 / 254 tests on two consecutive runs; flight bench clean.
- Still NOT matched: F-22 chined nose, Concorde wing kink / nacelle shape, 747 engine and pylon shape, A-10 tail shape, and every fuselage side/front outline (only planforms were fitted).

### Reference pass 6 (2026-10-06): side-view fit
- Reference evidence (scratchpad `/tmp/claude-0/ref/`, never shipped): photo + three-view for Cessna 150 (c150_a.jpg, c150_3v), Super Cub (cub_a.jpg, cub_3v), P-51D (p51_side.jpg, p51_3v), F-22 (f22_a.jpg, f22_3v), A-10 (a10_a.jpg, a10_3v), F-16 (f16_prof.jpg, f16_3v), Concorde (concorde_a.jpg, concorde_3v), 747-400 (b747_a.jpg, b747_3v), C-130 (c130_a.jpg, c130_3v). All fetched from Wikimedia Commons via Special:FilePath with a User-Agent and pauses.
- Side view: `tools/outline_fit/side*.py` extract the upper contour (canopy / hump / fin line) of each three-view's side drawing; a bounded search (+-15 % of fuselage half-height per station, top edge only) was applied to Skylark, Tundra Cub, Brute 10, Skyliner, Cargomaster and Striker (all flight tests still green). Offset-free RMS error as % of length, now: Skylark 1.1, Tundra Cub 2.0, Belle 51 3.4, Specter 22 3.2, Brute 10 3.3, Striker 1.5, Mach Arrow 3.8, Skyliner 3.5, Cargomaster 1.6.
- New test "scale: side-view upper contour matches the real type's drawing" using derived 40-sample contours in `tests/reference_side.json` (no image shipped).
- Limits: the side fit covers only the upper contour (gear, props, nacelles and the belly line were excluded because they distort the silhouette), fin shape only through the fuselage-plus-fin outline, and no front-view fit exists. F-22 chined nose, Concorde nacelles and wing kink, 747 pylons and A-10 tail shape were not matched by measurement.

## Automated suite (`-- --test`): 28 / 28 PASS
- **PASS** transmitter: Linear preset is exactly linear
- **PASS** transmitter: expo softens centre
- **PASS** save: v1->v3 migration keeps zero values  -- { "assist": "expert", "damage": "physical", "aftermath": 0.0, "slowmo": 0.3, "landing_feedback": true, "camera": "pilot", "auto_zoom": true, "un
- **PASS** save: corrupted file falls back to defaults
- **PASS** rest on gear: skylark settles without damage  -- vel=0.001 dmg=0.00
- **PASS** rest on gear: tundra_cub settles without damage  -- vel=0.000 dmg=0.00
- **PASS** rest on gear: viper90 settles without damage  -- vel=0.000 dmg=0.00
- **PASS** rest on gear: skyliner settles without damage  -- vel=0.000 dmg=0.00
- **PASS** landing gear absorbs ordinary touchdown (1.3 m/s sink)  -- dmg=0.00 det=[] peak_load_ratio=[4.8, 2.5, 2.6]
- **PASS** hard landing (3.6 m/s sink) loads/bends gear but airframe survives  -- bent=0.20 det=[] peak_load_ratio=[13.0, 8.5, 8.4]
- **PASS** slow wingtip scrape does NOT trigger a crash  -- dmg=0.00
- **PASS** stationary tilted aircraft touching a wing does not break  -- dmg=0.00 crashed=false det=[]
- **PASS** prop strike stays localised (prop damaged, airframe intact)  -- prop_hit=true detached=["prop0"] crashed=false
- **PASS** high-speed wing vs tree: wing damaged/detached  -- { "passed_through": true, "cross_y": 2.24, "crashed": true, "det": ["nose", "canopy", "wing0_L", "tip0_L", "flap0_L_1", "ail0_L_3", "ail0_
- **PASS** 60 m/s jet cannot tunnel through a tree trunk  -- { "passed_through": false, "cross_y": -1.0, "crashed": true, "det": ["wing0_L", "tip0_L", "ail0_L_1", "ail0_L_2", "wing0_R", "tip0_R", "ail
- **PASS** aircraft cannot fly through the clubhouse  -- { "passed_through": false, "cross_y": -1.0, "crashed": true, "det": ["tail_boom", "wing0_L", "tip0_L", "flap0_L_1", "ail0_L_3", "ail0_L_4", "wi
- **PASS** aircraft cannot pass through a pit table  -- { "passed_through": false, "cross_y": -1.0, "crashed": false, "det": ["nose", "canopy", "prop0"], "dmg": 7.91, "impact": 20.0 }
- **PASS** aircraft cannot pass through a parked aircraft  -- min_y=0.46 parked_y=0.31 impact=3.8
- **PASS** aircraft collides with a person (knocked down, no pass-through)  -- npc_down=true { "passed_through": false, "cross_y": -1.0, "crashed": true, "det": ["wing0_L", "tip0_L", "ail0_L_1", "ail0
- **PASS** vegetation acts as soft drag (hedge slows the aircraft)  -- vmin=0.3
- **PASS** safety fence/netting stops the aircraft  -- { "passed_through": false, "cross_y": -1.0, "crashed": true, "det": ["canopy", "wing0_L", "tip0_L", "flap0_L_1", "ail0_L_3", "ail0_L_4", "tip0_R"
- **PASS** major crash: components detach as real rigid bodies  -- debris=6 moved=6 det=["tail_boom", "nose", "canopy", "wing0_L", "tip0_L", "ail0_L_1", "ail0_L_2", "stab_L", "elev_L", "stab_R", "elev
- **PASS** losing a wingtip changes mass, CG and makes the aircraft roll  -- dm=0.078 dcg.x=0.0331 roll=-0.98 rad
- **PASS** rewind restores state and repairs parts broken afterwards  -- broke=21 after=[] y=30.0
- **PASS** replay buffer records, scrubs and restores  -- frames=300 move=20.0
- **PASS** 50 repeated crashes: no object growth  -- objects 14450 -> 14458
- **PASS** 50 repeated crashes: crash #50 not worse than #1 (headless CPU frame)  -- worst frame first=1.83ms last=2.34ms
- **PASS** all 16 aircraft spawn and rest on their gear cleanly  -- bad=[]

The "50 repeated crashes" frame times are **headless CPU frame times on the build container**, not device render times.

## Flight envelope (`tests/flight_test.tscn`), all 16 aircraft
All 16 aircraft: rest level on their gear, take off under the scripted test pilot without damage (takeoff speed / distance per aircraft in the log), reach a stable max speed, roll, spin and recover when controls are neutralised. Loops complete for 15/16 with full up elevator; the Viper 90 at 38 m/s with **full** up elevator performs an accelerated-stall snap roll over the top (emergent, not scripted); with 70 % elevator it loops cleanly.

Bugs found & fixed in this QA pass:
- Tail wheel steered in the same direction as a nose wheel (ground loops) → reversed.
- Taildraggers had no level-attitude propeller clearance → prop struck when the tail lifted. Clearance rule now applies to all gear types.
- Fuselage collision boxes overhung the tapering tail, so the tail rested on the collider instead of the tail wheel → replaced with tapered convex hulls that follow the loft.
- Losing the nose/engine now counts towards structural breakup.

## Rendering statistics (lavapipe, 1600×740, Medium quality)
Draw calls ≈ 175–250 and ≈ 170k–940k primitives depending on view (typical flight view ≈ 180 draws / 230k prims). These are **counts**, not performance measurements. Software rendering FPS is meaningless for Android and is not reported.

## Manual checks done (via rendered screenshots)
Menu/hangar, all aircraft in the carousel, midday and golden-hour lighting, flight HUD, sticks, pause menu, settings tabs, kill-cam UI, landing and gates modes, crash debris.
