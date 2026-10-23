# RC PARK — Android RC airplane simulator (Godot 4.7)

Native Godot 4.7.2 project (Mobile renderer, Jolt physics @ 120 Hz, landscape, touch-first).
Everything — aircraft, terrain, trees, field props, textures, sounds — is generated procedurally
at load time from code in this repository. No third-party models, textures or audio are shipped.

## Install on your phone
**Download:** https://github.com/MrLeefy/RC-PLANES/releases/latest/download/RCPark.apk

Open that link on the phone, then tap the downloaded file and allow "install unknown apps" for your
browser when Android asks. Android 7.0+ (arm64).

Every push to `main` is tested, built and published as a new release automatically, so the same link
always serves the newest build. To get updates without re-downloading by hand, install
[Obtainium](https://github.com/ImranR98/Obtainium) and add `https://github.com/MrLeefy/RC-PLANES` —
it notifies you and installs each new release.

Builds older than v0.11 (the "RC Park Preview" APKs) were signed with a different key: uninstall that
once before installing a v0.11+ build. After that, updates install over each other and keep your settings.

## Playing
- Menu (hangar): pick aircraft in the carousel, set Mode / Time / Wind / Launch-from / Assist / Damage at the top, tune in the Workshop panel on the right, press **FLY**.
- Assist: **Arcade** self-levels and limits bank/pitch (easiest). **Sport** (default) is full aerobatics with a
  heading-hold gyro: let go of a stick and the plane holds its attitude. **Expert** is raw, no help.
- Default sticks are Mode 2 (left: throttle + rudder, right: elevator + aileron). Change mode, expo, rates, deadzone, trims and presets under Settings → Transmitter. The "Linear / Direct" preset is truly 1:1.
- HUD: pause, camera, 5 s rewind, instant replay, engine start/stop, flaps, gear, reset.
- After a crash: live aftermath → kill-cam replay (skip / pause / speed / scrub / watch again / **Repair & Fly**).

## Building
CI does this for you (`.github/workflows/android.yml`). To build locally you need Godot 4.7.2 with its
export templates, the Android SDK (build-tools) and a JDK 17+:

```sh
ANDROID_SDK_ROOT=~/Android/Sdk JAVA_HOME=/usr/lib/jvm/java-17 ci/build_android.sh   # -> build/RCPark.apk
```

Release signing: the `RC_SIGNING_SEED` repository secret (any password, 16+ characters) is turned into the
same signing key on every build by `ci/make_keystore.py`, so no keystore file is stored anywhere. Keep that
secret safe and never change it: a different seed means a different key, and phones would need to uninstall
before updating. Without the seed, local builds use a throwaway key.

Play Store AAB: use preset **"Android Play (AAB, needs Gradle)"** (Project → Install Android Build Template first, Android SDK 35 + JDK 17 required), then `--export-release "Android Play (AAB, needs Gradle)" build/RCPark.aab`.

## Tests
- `godot --headless --fixed-fps 120 --path . -- --upgrade-test` → full suite (248 checks: physics, crashes, saves, replay, all 16 aircraft). CI runs this on every push.
- `godot --headless --fixed-fps 120 --path . -- --test` → quick 28-test core suite.
- `godot --headless --fixed-fps 120 --path . res://tests/flight_test.tscn` → per-aircraft flight envelope numbers.

See `docs/` for architecture, aircraft data, assets/licensing, QA report and the list of unverified items.
