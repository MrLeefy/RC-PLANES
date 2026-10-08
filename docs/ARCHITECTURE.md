# Architecture

## Autoloads
| Node | File | Role |
|---|---|---|
| Settings | scripts/autoload/settings.gd | Versioned JSON save (v3), deep-merge that preserves zero values, v1→v2→v3 migration, corrupt-file backup + reset, TX profiles (global / per-aircraft / named), aircraft workshop configs |
| Game | scripts/autoload/game.gd | Collision layers, surface table (friction / rolling resistance), refs to field/wind/fx/flight |
| Sfx | scripts/autoload/sfx.gd | Procedurally synthesized sound bank (cached to user://), buses Engine/SFX/Ambience/UI + limiter, pooled players |
| Diag | scripts/autoload/diag.gd | Frame-time ring buffer, input/collision/event logs, JSON diagnostics export |

## Boot (scripts/game/main.gd)
Loading screen → wind → `Field.build_async` (terrain, runway, pits, trees, grass, NPCs) → `Sfx.build_bank_async` → Fx pools → shader/particle prewarm → hangar menu. Graphics settings apply render scale (bilinear; FSR is unavailable on the Mobile renderer), MSAA, mesh LOD threshold, FPS cap; optional automatic resolution scaling.

## Aircraft pipeline
`AircraftDB` (pure data, 16 aircraft) → `AircraftBuilder.build(def, cfg)` produces meshes (lofted fuselage, NACA surfaces, hinged control surfaces, props/fans, gear with oleo/steer/retract parts, livery painting, 3 LOD levels), component tree (for damage), aero panels, engines, wheels, mass distribution, inertia and collision shapes → `Aircraft` (RigidBody3D, custom COM + inertia).

Per physics tick (`Aircraft._integrate_forces`, 120 Hz):
1. Wind at each panel (gusts, turbulence, log shear) + prop-wash.
2. `Propulsion` per engine: electric (Kv/Rm/i0 with battery sag and LVC), glow 2/4-stroke, gas, EDF, turbine (spool, start sequence, fuel burn). Thrust, torque, P-factor, gyroscopic precession.
3. `_aero`: every lifting panel computes local velocity, AoA, sideslip, downwash, control deflection (ΔCL/ΔCd/ΔCm), stall blend (Beard–McLain), post-stall flat-plate, ground effect. No attitude or rate limits; stalls, spins and snaps emerge from panel physics.
4. Body drag, foliage drag (soft), landing gear raycast suspension with friction circle and steering.
5. Contacts → impulse-based damage. Components have HP and thresholds by material; damage transmits to parents; parts detach into pre-pooled `DebrisBody`s (mass, CG and inertia recomputed).

Assist modes (Arcade / Sport / Expert) only alter the stick-to-surface mixing in `_mix_controls`; they never clamp the aircraft state.

## Flight state machine (scripts/game/flight.gd)
FLYING → (crash) AFTERMATH (live physics continue) → KILLCAM (replay, slow-mo profile) → KILLCAM_END panel → Repair & Fly / Watch again / Menu. Also REPLAY (instant replay), PAUSED. Snapshots every 0.1 s give a 5 s rewind; `Replay` records a 60 Hz ring buffer (26 s) of aircraft + debris transforms.

## Modes (scripts/game/modes.gd)
Free flight, Landing practice (graded touchdown), Crosswind, Engine-out, Touch & Go, Aerobatics (loop/roll/spin/inverted detection), Gates, Time trial, Ghost (best lap saved to user://ghost_<id>.json).

## World
`Field`: 385² heightfield over ±1200 m (single HeightMapShape), chunked terrain meshes, asphalt runway, flight-line fence with gaps, pilot stations, pits, clubhouse, shed, parking, perimeter fence, windsock driven by the sim wind, parked aircraft (merged mesh), trees (TreeLib species, near/far visibility ranges, trunk colliders, soft canopy Areas), grass MultiMesh tiles swaying with the shared wind globals, NPCs (kinematic walkers that become ragdoll-lite rigid capsules when knocked, then get up).
`Wind` pushes `wind_dir/strength/gust` to shader globals, so grass, trees and the windsock match the forces on the aircraft.

## Performance design
- Aircraft builds are the main CPU cost (about 0.8–1 s each on the build container). Paint is evaluated per vertex and per anti-aliasing tap, so its fuselage lookup comes from a 257-sample table built once per builder (`AircraftBuilder._paint_fus`).
- The hangar keeps the last four display aircraft built and hidden (processing disabled). The two carousel neighbours are prebuilt one at a time while the player is idle (`main.gd` `_display_for`, `_prebuild_neighbours`). Workshop edits drop that aircraft's entry, and starting a flight clears the cache.
- Crash rule: a contact with normal closing speed ≥ `CRASH_CLOSING_MPS` (15 m/s) is a crash, even when the nose, prop or gear tears away first (`aircraft.gd` `_contacts` and the swept-probe path).
- All crash effects are pooled (chips, particles, debris bodies, audio players) → no allocation at crash time (tested: 50 crashes, object count stable).
- Static props merged; tree chunks share meshes; visibility ranges + mesh LODs; shadows focused around the camera.

## Collision layers
WORLD 1, AIRCRAFT 2, DEBRIS 4, FOLIAGE 8, NPC 16, GATE 32, CHIP 64.
