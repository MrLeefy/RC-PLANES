# RCBeam — mobile node/beam structural physics

RCBeam is the planned native structural solver for RC Park. Its goal is BeamNG-style *physical* crash deformation at mobile-friendly cost, without copying BeamNG or GPL code.

## Clean-room reference policy

Use public behavior/documentation as references, then implement independently:

- **BeamNG documentation** — node/beam concepts, spring/damper beams, permanent deformation, break strength/groups, flexbody-style visual deformation.
- **Rigs of Rods** — useful architectural reference for node/beam vehicle simulation, but its GPLv3-or-later source is **reference only**. Do not copy/adapt RoR source into RCBeam.
- **Bullet Physics** — permissive zlib reference for real-time collision/soft-body techniques.
- **Project Chrono** — permissive BSD-3 reference for flexible-body and mechanical-system numerical techniques.

RCBeam production code must remain our own clean-room implementation or use only dependencies whose licenses are compatible with the project.

## Why a custom solver

A 100k–300k triangle aircraft should never become 100k–300k physics particles. The visual mesh is presentation. The structural skeleton is small:

| Aircraft class | Target nodes | Target beams |
| --- | ---: | ---: |
| Foam trainer | 45–70 | 160–280 |
| Aerobatic / warbird | 70–110 | 250–450 |
| Large EDF / turbine | 90–150 | 350–650 |

The node/beam graph models spars, longerons, ribs, firewall, motor mount, gear mounts, wing joiners, tail attachment and selected skin bracing.

## Runtime architecture

```
Godot/Jolt rigid-body world @ 120 Hz
        |
        | contact impulses / world motion
        v
RCBeam native C++ structural solver
  normal: 4 substeps  -> 480 Hz
  impact: 8 substeps  -> 960 Hz for a short bounded window
        |
        +-- node positions / velocities
        +-- beam strain / plastic deformation
        +-- break events + break groups
        +-- damage energy
        |
        v
visual deformation / detached rigid assemblies / aero state
```

The structural solver does not replace Jolt. Jolt owns broad-phase world collision, terrain, props, detached rigid pieces and the aircraft's coarse body. RCBeam owns internal structural compliance, permanent deformation and fracture.

## Performance rules

1. **No per-frame heap allocation.** Node, beam, force and event buffers are reserved and reused.
2. **Structure, not render mesh, is simulated.** Render vertices follow a small node cage.
3. **Adaptive work is bounded.** Higher substep counts are enabled only for a short impact window and have a hard maximum.
4. **Debris has a budget.** Major assemblies become Jolt bodies; tiny splinters/chips are pooled visual particles rather than permanent rigid bodies.
5. **Sleeping is aggressive after the crash settles.**
6. **Collision is hierarchical.** Coarse hulls during flight, local structural impulses around actual contacts during crashes.
7. **LOD affects structural detail only when safe.** The player's active aircraft keeps the authoritative structural graph; distant parked aircraft do not run RCBeam.
8. **Replay records structural state compactly** (node offsets / broken beam bitsets or keyframes), not the full render mesh.

## Beam model

Every beam has:

- initial and current rest length
- stiffness (N/m)
- damping (N·s/m)
- tension/compression yield strain
- tension/compression break strain
- plastic flow rate and plastic-strain cap
- optional break-group id

A step computes spring + damping force from the current beam length and relative endpoint velocity. Crossing yield changes rest length permanently. Crossing break strain disables the beam. A break group can release an assembly (wing bolts, canopy, motor firewall, battery tray, landing gear mount).

## RC material presets

Initial values are *tuning seeds*, not certified material data. They must be validated against RC crash footage, component dimensions and drop/impact tests.

- **EPO/EPP foam:** compliant, high damping, early yield, large plastic/crush range.
- **Balsa/film:** stiff along grain, low plasticity, relatively brittle.
- **Plywood/firewall:** stiffer and tougher than balsa; localized splitting.
- **Carbon spar:** very stiff, little plastic deformation, abrupt fracture.
- **Aluminum gear:** stiff with meaningful plastic bending before failure.
- **Steel wire:** high elastic range, bends plastically under severe overload.

Long term these presets should become orthotropic where needed (especially wood and composites), because an RC wing spar is not mechanically isotropic.

## Visual deformation

The high-detail aircraft mesh will be authored with a low-count deformation cage. Each render vertex stores a few nearby structural-node weights. The GPU skins the visual mesh from structural node transforms; CPU never updates individual render vertices.

Break events can also:
- disable triangles bridging separated assemblies,
- expose fracture/interior meshes,
- swap crack/foam-crush material masks,
- spawn pooled dust, foam, balsa or composite fragments.

## Aerodynamics coupling

The current per-panel aerodynamics remains authoritative first. RCBeam deformation then feeds it:

1. structural node cage deforms,
2. wing/tail panel anchors and normals follow the cage,
3. local incidence/dihedral/twist change naturally,
4. broken structural regions lose panel area,
5. detached assemblies stop producing force on the parent aircraft.

This allows a bent wing to create asymmetric lift without a generic "damage multiplier."

## Milestones

### M1 — native core
- compact node/beam types
- spring/damping
- plastic rest-length deformation
- tension/compression fracture
- break groups
- adaptive bounded substeps
- no-allocation stepping
- deterministic smoke tests

### M2 — Godot bridge
- GDExtension wrapper
- build for desktop + Android arm64
- feed contact impulses from Aircraft/Jolt into nearby structural nodes
- expose node transforms and beam events

### M3 — one-aircraft proof
- high-detail aircraft model
- 50–100-node structural cage
- wing spar, firewall, gear and tail failure
- visual cage skinning
- replay/rewind state

### M4 — production
- structural templates by aircraft construction
- authoring/import tooling
- automatic node/beam validation
- physics profiling on real Android hardware
- crash regression suite and deterministic replay
