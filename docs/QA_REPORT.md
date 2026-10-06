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
- Not yet done from the photos: re-modelling the P-51, F-16, A-10, Concorde and 747 outlines against the 3-views (only the C-130 was reworked this round), and no texture photos are used.

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
