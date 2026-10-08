# Google Play preparation

## Status — RC Park 1.0.0-beta.1 (versionCode 10000)

| Item | State |
|---|---|
| AAB builds with Gradle and passes `bundletool validate` (bundletool 1.17.2) | Verified (build container). Signed with a **throwaway verification key**, not a release key. |
| Debug APK builds and passes `apksigner verify` (v2/v3) | Verified (build container). |
| Manifest: arm64-v8a only, minSdk 24, targetSdk 36, no `uses-permission` entries | Verified with `bundletool dump manifest` and `aapt2 dump badging`. |
| Automated suite (247 checks) and per-aircraft flight envelope | Passing on the build container (software Vulkan for rendering). |
| Install and run on a physical Android device | **Not done.** Needs a phone. |
| Upload to Play Console, internal/closed testing track | **Not done.** Needs your Play account and your upload key. |
| Phone screenshots (2–8, from a device) | **Not done.** See "Store assets". |

## Package / versioning
- Application ID: `com.rcpark.sim.upgrade` (both presets). **Decide before the first upload:** the ID cannot be changed once published. `docs/PLAY_STORE.md` earlier suggested `com.rcpark.sim`; the `.upgrade` suffix was a preview choice so it could not clash with the original 0.9.0 install (see `UPGRADE_README.md`). Change it in `export_presets.cfg` (both `package/unique_name` lines) if you want the clean ID.
- Version: `versionName "1.0.0-beta.1"`, `versionCode 10000`. Rule for later uploads: `MAJOR*10000 + MINOR*100 + PATCH` (1.0.1 → 10001, 1.1.0 → 10100). Always increase it for every upload.
- minSdk 24 (Android 7.0). targetSdk 36. arm64-v8a only (add armeabi-v7a in the AAB preset only if you want 32-bit devices, and test that path). Check the current Play target-API requirement in the Play Console before upload.

## Build
1. Godot 4.7.2 stable with matching export templates (`4.7.2.stable`).
2. Android SDK: `platform-tools`, `platforms;android-36`, `build-tools;35.0.0`. Set the SDK and JDK paths in Godot's editor settings (`export/android/android_sdk_path`, `export/android/java_sdk_path`). JDK 21 worked here; JDK 17 is the documented baseline.
3. Install the Android build template into the project (creates `android/`, which is git-ignored and excluded from the export):
   - Editor: Project → Install Android Build Template, or
   - Manual: unzip the templates' `android_source.zip` into `android/build/` and write `4.7.2.stable` to `android/.build_version`. (The headless `--install-android-build-template` call did not finish in the build container.)
4. Keys (never commit them):
   - Create the upload key: `keytool -genkeypair -v -keystore upload.jks -alias upload -keyalg RSA -keysize 4096 -validity 10000`.
   - Pass it at export time with `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `GODOT_ANDROID_KEYSTORE_RELEASE_USER`, `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD`.
5. Export: `godot --headless --path . --export-release "Android Play (AAB, needs Gradle)" build/RCPark.aab`.
6. Check: `java -jar bundletool.jar validate --bundle=build/RCPark.aab` and `java -jar bundletool.jar dump manifest --bundle=build/RCPark.aab`.
7. Gradle downloads from Maven Central. In the build container Maven Central returned HTTP 429 (rate limit) on the first attempt; the retry succeeded. Retry after a few minutes if you see the same.

## Signing
Play App Signing: Google holds the app-signing key; you upload with the upload key from step 4. Keep the upload key and its passwords out of the repository.

## Permissions
None requested (no INTERNET, no storage permissions; saves go to app-private storage). Verified in the AAB manifest.

## Data safety form (draft, checked against the code)
- Data collected: **none**. Data shared: **none**.
- Checked: no network code (no `HTTPRequest`, sockets, WebSockets or URLs) in `scripts/`, `shaders/` or `scenes/`.
- Checked: all writes go to `user://` (app-private): settings, ghost laps, sound-bank cache and the optional diagnostics JSON, which is written only when the user presses the export button and is never transmitted.
- The app has no accounts, analytics, ads or third-party SDKs.

## Privacy policy (draft text)
> RC PARK does not collect, store remotely, or share any personal information. All settings, replays and ghost laps are stored only on your device, in the app's private storage, and are deleted when you uninstall the app. The app does not use the internet, advertising, analytics, or third-party SDKs. Contact: <your email>.

## Content rating
Non-violent flight simulation; figures can be knocked over by aircraft with no blood or injury depiction. Expected IARC: Everyone / PEGI 3 (confirm via the questionnaire).

## Store assets
- Hi-res icon: `docs/store/icon-512x512.png` (512×512 RGBA, from `icon.png`). Ready.
- Feature graphic: `docs/store/feature-graphic-1024x500.png` is a **draft**: a software-rendered hangar frame with text overlaid. Replace it with final art.
- Phone screenshots: at least 2 are required. Take them on a real device at the target aspect ratio (the software renders in this container are not representative of phone output).
- Optional: tablet screenshots and a short video.
