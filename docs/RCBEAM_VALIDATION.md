# RCBeam integration validation — 2026-10-07

Branch: `codex/structural-crash-realism`; draft PR #2. Main is untouched.

## Reproducible toolchain

Godot 4.7.2 stable (`ed1daf0bf`), godot-cpp `ed672dc12ed37c8b361fe077285a094882ad0543`, SCons 4.11.1. Windows native tests use LLVM-MinGW Clang 22. Android release build uses NDK 25.2.9519653, ARM64, API 24. See `native/rcbeam/godot/README.md` for commands and host-library installation.

The previous Linux command forced x86_64. The `-m64` rejection is consistent with selecting an ARM64 compiler for that target; the original host is unavailable in this checkout, so this is a diagnosis from toolchain behavior rather than a reproduction on that host. Native Linux builds now detect their architecture, and a compiler preflight rejects unsupported target flags. Two additional compile failures were reproduced and fixed: missing OS in the reduced bindings profile, and missing material-enum Variant registration.

## Results

| Check | Result |
| --- | --- |
| Windows Godot 4.7 GDExtension compile/load | PASS |
| Android ARM64 template_release compile | PASS; device runtime not tested |
| Native smoke, optimized build with assertions enabled | PASS |
| Native regression: force duration at 4/8 substeps, impulse conservation, hard substep cap, plasticity, fracture | PASS |
| Native hot path: 140 beams, 70 break groups, 120 steps plus indexed event clearing | PASS; zero calls to operator new after initialization |
| Godot structural/aero/contact tests | PASS, 34/34 |
| Legacy crash/save/replay suite | PASS, 28/28 |
| Flight envelope diagnostic scene | Completed for all 16, `DONE`; diagnostic rather than pass/fail assertions |
| Workshop matrix before gear-data fix | FAIL, 3/104; Valor 4.459 g, Tiger 6.036 g, Brute 2.869 g mass mismatch at -6% MAC |
| Workshop matrix after gear-data fix | PASS, 104/104; worst mass <0.000001 kg, CG 0.000361 m, relative inertia 0.003213 (0.3213%); panel data/counts/prop parameters match |
| Linux x86_64 / ARM64 native builds and Godot tests | Pending CI |

Local logs are under ignored `build/`: `extension-build.log`, `android-build.log`, `baked-matrix.log` (initial failure), `baked-matrix-fixed.log`, `rcbeam-aero-test.log`, `legacy-suite.log`, `flight-suite.log`. CI logs are linked from PR #2. Full logs are not standing project instructions.

## What is integrated

- Real Jolt contact vectors are transformed to the aircraft's local frame and conservatively distributed over nearby unpinned nodes.
- Local cages are pinned to Jolt's coarse fuselage. Jolt remains responsible for global motion; gravity is not applied twice and contact impulses are not fed back into the rigid body.
- Skylark: 52 nodes / 270 beams. Generic cages on all 16 models: maximum 72 nodes / 380 beams. Spar, skin, firewall/mount, gear, tail and nacelle members use separate proof tuning seeds; internal members and attachment break groups are distinct.
- Tests verify ten seconds without drift, intact flight-force equivalence, changed force/torque after asymmetric bending, wing lift loss after release, four distinct destructive attachment cases, repair, a real Jolt drop and a six-body debris limit.
- Bounds: 4 normal / 8 impact substeps; oversized (>1/30 s), nonpositive and nonfinite frame durations are rejected. Native event buffers retain capacity.
- Premade visuals receive an affine transform per tetrahedral component cage. Aerodynamic panel positions, forward vectors, inverse-transpose normals and areas follow it. Released panels and controls stop contributing to the parent, including when debris capacity is exhausted.

## Limits before production enablement

This is an opt-in physical proof (`-- --rcbeam-proof`), not a completed BeamNG-equivalent simulation. Material constants need RC-scale calibration. The fuselage anchoring is simplified. Four-node component cages provide affine bending/crushing; smooth GPU flexbody skinning, interiors and detailed cracks remain future work. Aerodynamic loads do not yet drive structural deformation; contact-induced structural deformation does drive aerodynamics.

No-allocation guarantees currently cover the native solver step and indexed event API. The GDScript visual/aero adapter has not been allocation-profiled on Android and should move more work into native code before enabling it by default. Android compilation does not establish device performance or APK export success.

Structural state is not yet serialized for replay/rewind. Restoring a snapshot resets aerodynamic geometry and disables the proof, using the established legacy replay/damage path. Repair rebuilds pristine structural state. Old procedural models remain the fallback; updated static artwork must retain the blueprint's hierarchy and references.
