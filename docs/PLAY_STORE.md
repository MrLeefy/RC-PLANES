# Google Play preparation

## Package / versioning
- Package: `com.rcpark.sim` (change before publishing if you own a different namespace).
- versionCode strategy: integer `MAJOR*10000 + MINOR*100 + PATCH` from 1.0.0 on (current pre-release: versionCode 9, versionName 0.9.0). Always increase for every upload.
- min SDK 24 (Android 7.0), target SDK 35. arm64-v8a only (add armeabi-v7a in the export preset if you want 32-bit devices).

## Signing
No keystore is included. For Play, use Play App Signing: create an upload key locally
(`keytool -genkeypair -v -keystore upload.jks -alias upload -keyalg RSA -keysize 4096 -validity 10000`),
and pass it at export time via `GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD` env vars. Never commit it.

## AAB
Play requires an Android App Bundle. Use export preset "Android Play (AAB, needs Gradle)":
Project → Install Android Build Template, Android SDK (platform 35, build-tools 35), JDK 17, then export release.
This AAB could not be built in the environment used to create this project (no access to Google's Maven/SDK), so it has **not been produced or tested**.

## Permissions
None requested (no INTERNET, no storage permissions; saves go to app-private storage).

## Data safety form (draft)
- Data collected: **none**. Data shared: **none**.
- The app has no network code, analytics, ads, or accounts.
- Diagnostics export writes a JSON file to app-private storage only when the user presses the button; nothing is transmitted.

## Privacy policy (draft text)
> RC PARK does not collect, store remotely, or share any personal information. All settings, replays and ghost laps are stored only on your device, in the app's private storage, and are deleted when you uninstall the app. The app does not use the internet, advertising, analytics, or third-party SDKs. Contact: <your email>.

## Content rating
Non-violent flight simulation; figures can be knocked over by aircraft with no blood or injury depiction. Expected IARC: Everyone / PEGI 3 (confirm via the questionnaire).

## Store assets still needed
512×512 icon (can be derived from `android_assets/icon_192.png` source script at higher res), 1024×500 feature graphic, phone/tablet screenshots from a real device.
