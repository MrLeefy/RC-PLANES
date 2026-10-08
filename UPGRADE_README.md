# RC Park 0.10.0 — implementation preview

> **Status update (1.0.0-beta.1, 2026-10-08):** the release status, verified checks and open items are in `docs/PLAY_STORE.md` and `docs/QA_REPORT.md`. The sections below describe the 0.10.0 preview as it was delivered.

## Status and important limits
This package contains actual edited Godot source, not a new APK and not a claim of completed QA. The original user-uploaded APKs have not been changed or relabelled as an upgraded build.

The code changes listed below are implemented in the source. A successful native Godot import, regression run, rendered visual review, Android export and physical-device test have NOT been verified for this delivery. The supplied regression tests are newly written tests, not a passing test report. Treat this as an engineering preview pending validation, not a production-ready release.

The standard Godot 4.7.2 ARM64 executable was obtained in an isolated Oracle build directory, but the observed validation attempts did not produce a confirmed successful test result. No production server configuration was intentionally changed. The source is also provided locally so validation does not depend on that server.

## Preserve the original installation
The preview uses version 0.10.0 / versionCode 10 and the separate application ID `com.rcpark.sim.upgrade`. This avoids pretending that a newly test-signed build can update an installation signed with the original key. The source retains all 16 aircraft and the flight, damage, live-aftermath, kill-cam, replay, repair, workshop and challenge systems. Save transfer between separate application IDs is not implemented.

## Core implementation changes
| Audit item | Changes implemented | Validation status |
|---|---|---|
| R01 | Frame-cap-aware dynamic resolution recovery, warm-up, hysteresis, cooldown, quality ceiling and CPU-bound safeguards. | Regression tests added; not verified passing. |
| R02–R03 | Altitude-aware cinematic shots, minimum shot timing, recorded-aircraft camera focus and collision/terrain avoidance for additional views. | Regression tests added; motion and camera obstruction still need rendered testing. |
| R04 | Broader aircraft snapshots, throttle/brake/transmitter restoration, debris state and collision-exception restoration. Rewound challenges become practice attempts. | Regression tests added; not verified passing. |
| R05 | Independently preserved impact clips, bounded aftermath recording, replay session state separate from pause/end state, and live-state restoration after seek/restart. | Regression tests added, including long aftermath retention and real Flight lifecycle loops; not verified passing. |
| R06 | Centralized Android Back/modal routing, closing Settings without resuming a paused flight, settings reapplication on resume. | Automated scenario added; Android navigation still requires device testing. |
| R07–R09 | Tangential contact-velocity correction, upward-support ground classification, separate AGL query beyond the short ground-effect probe and unknown-altitude display. | Math and physics tests added; Jolt contact-normal coordinate behavior must be verified. |
| R10 | Spatially indexed outer-canopy drag with a bounded drag impulse; consistent tree population across quality presets. | Regression tests added; canopy/trunk behavior needs flight testing. |
| R11–R12 | Canceled-touch handling, touch ownership cleanup, safe-area-aware controls, multi-finger orbit/pinch ownership and gamepad/touch handoff changes. | Synthetic-event tests added; real multitouch and controller tests remain necessary. |
| R13 | Impact contact speed kept distinct from severity, with preserved crash cause/part metadata. | Not runtime-verified. |
| R14 | Bounded validated ghost files, monotonic timestamps, quaternion checks, configuration-sensitive record keys and durable file writes. | Corrupt/setup-mismatch tests added; not verified passing. |
| R15 | Live grass-density updates using visible instance counts and explicit quality round trips, including glow. | Regression tests added; device performance is unmeasured. |
| R16 | Removed selected temporary allocations and replaced untracked debris timers with snapshot-compatible countdown state. | No allocation-free or performance improvement claim is made. |
| R17 | Stronger advertised no-pass-through assertions and an additional full Flight crash/replay/repair lifecycle suite. | Tests exist; no new pass count is claimed. |
| R18 | Validated nested settings, finite/range checks, backup recovery, future-schema read-only handling, checked saves and truthful export locations. | Regression tests added; not verified passing. |
| R19 | Broader replay visual state, debris/NPC/effect snapshots and recorded-time audio handling. | Rendered/audio synchronization still needs verification. |
| R20 | Larger telemetry option, more mobile-oriented hangar/settings/replay controls, safe-area layout and clear impact/playback indicators. | Layout source updated; screenshots at target aspect ratios still needed. |

## Visual and audio changes — scope matters
The visual work is a procedural-material and UI upgrade, NOT a finished artist-authored texture/model replacement.

- Runway: shared mipmapped procedural textures, derivative-filtered fine detail, less bright aggregate noise, subtler cracking/paint wear and more controlled roughness/bump.
- Aircraft: clearer foam/film/composite material differences, filtered small detail and lightweight construction-specific fracture interiors on selected separation boundaries. Fracture visibility follows component ownership and repair/replay state. This does not model every internal component or every possible fracture boundary.
- Environment: revised terrain detail filtering, bark/wood/fabric treatments, curved grass geometry and quality-controlled density. No claim of higher FPS or lower battery usage is supported yet.
- Mobile presentation: simpler default hangar, expandable advanced setup/workshop, safe-area controls, replay timing/impact markers and gesture surfaces.
- Audio: replay-clock-driven behavior, bounded one-shot recording, seek/pause cleanup and replay Doppler handling. No professionally recorded sound bank was added and phone-speaker loudness/latency has not been heard or measured.

## Validation commands
Use a STANDARD (non-Mono) Godot 4.7.2 installation and matching Android export templates. From the project directory:

```sh
godot --headless --editor --import --path . --quit
godot --headless --path . -- --upgrade-test
godot --headless --path . tests/flight_test.tscn
```

Check logs for `SCRIPT ERROR`, `Parse Error`, shader errors and failed assertions even when an engine invocation returns exit code zero. The upgrade runner extends the original baseline runner. Do not count the old 0.9.0 QA report as verification of this source.

For Android, configure the Android SDK, Java SDK, matching templates and an appropriate preview signing key in Godot, then export the existing Android APK preset. Verify the resulting package, alignment and signature. Install as the separate preview package and validate touch, Android Back, app interruption/resume, sound, safe areas, thermal behavior, memory and extended play before release.

## Recommended acceptance sequence
1. Resolve import/parser errors, then pass baseline and added regression suites and all 16 aircraft flight-envelope tests.
2. Render matched before/after hangar, runway, midday/golden-hour scenery, crash and replay views. Fix visual regressions rather than relying on static shader inspection.
3. Exercise a one-minute live aftermath followed by replay; seek/end/restart; rewind at nonzero throttle; repeated real Flight crash/replay/repair cycles; and Settings plus Android Back during pause.
4. Export, align and verify a signed APK, then measure a real phone. Include canceled touches, simultaneous sticks and buttons, phone interruptions, narrow/notched screens and longer sessions.

## Included files
The source ZIP is the complete local edited project, with assets and added regression tests, excluding generated caches and Git internals. The companion patch includes new source files. This document records implementation scope and explicitly does not certify a successful compile or finished release.
