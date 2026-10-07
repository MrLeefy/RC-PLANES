# RC PARK — Android RC airplane simulator (Godot 4.7)

Native Godot 4.7.2 project (Mobile renderer, Jolt physics @ 120 Hz, landscape, touch-first).
All 16 aircraft load premade scene/physics resources at default detail; Workshop settings update
data without rebuilding meshes. Terrain, trees, field props, textures and sounds are generated
from repository code. The original aircraft builder remains an offline tool and safe fallback.
No third-party models, textures or audio are shipped.

## Quick start
- Install: `adb install -r RCPark-debug.apk` (arm64-v8a, Android 7.0+ / API 24+).
- Menu (hangar): pick aircraft in the carousel, set Mode / Time / Wind / Launch-from / Assist / Damage at the top, tune in the Workshop panel on the right, press **FLY**.
- Default sticks are Mode 2 (left: throttle + rudder, right: elevator + aileron). Change mode, expo, rates, deadzone, trims and presets under Settings → Transmitter. The "Linear / Direct" preset is truly 1:1.
- HUD: pause, camera, 5 s rewind, instant replay, engine start/stop, flaps, gear, reset.
- After a crash: live aftermath → kill-cam replay (skip / pause / speed / scrub / watch again / **Repair & Fly**).

## Building
1. Godot 4.7.2 stable + matching export templates.
2. Open the project once (imports), then:
   - Debug APK: `godot --headless --export-debug "Android" build/RCPark-debug.apk`
   - Release APK: set env vars `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `..._USER`, `..._PASSWORD` to **your** keystore, then `godot --headless --export-release "Android" build/RCPark.apk`
   - Play Store AAB: use preset **"Android Play (AAB, needs Gradle)"** (Project → Install Android Build Template first, Android SDK 35 + JDK 17 required), then `--export-release "Android Play (AAB, needs Gradle)" build/RCPark.aab`.
3. No signing keys are included in this repository. Supply production signing yourself.

## Tests
- `godot --headless --fixed-fps 120 --path . -- --test` → 28 automated physics/crash/save tests, report in `user://test_report.json`.
- `godot --headless --fixed-fps 120 --path . res://tests/flight_test.tscn` → per-aircraft flight envelope checks.

See `docs/` for architecture, aircraft data, assets/licensing, QA report and the list of unverified items.

The optional RCBeam structural proof is enabled with `godot --path . -- --rcbeam-proof`
after building/installing the host GDExtension. Bending changes aerodynamic panels; attachment
fracture removes parent lift/control authority. See `docs/RCBEAM_VALIDATION.md` for results and
remaining mobile, calibration and replay work. The default path keeps the established physics.
