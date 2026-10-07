# Yag Touch

Android app that opens https://yag.im in a WebView and overlays configurable touch controls
(virtual stick, key buttons, mouse buttons, trackpad) so keyboard/mouse games are playable on a phone.

- **Browse mode** – plain touch for scrolling/picking games. **Play mode** – controller overlay.
- Stick sends WASD or arrow keys (switch in ☰ menu). Buttons send real Android key events.
- Mouse: *direct* (touch = click/drag at that spot) or *trackpad* (drag moves a red cursor, tap = click, 2-finger tap = right click).
- ☰ → Edit layout (drag, tap to resize/remove), Add button (any key, F1–F12, mouse buttons), Reset.
- Layout is saved on the device.

Build: `ANDROID_HOME=/path/to/sdk ./gradlew assembleRelease` → `app/build/outputs/apk/release/app-release.apk`.
Prebuilt: `YagTouch.apk` (debug-signed; enable "install unknown apps" to sideload).

Mouse events are injected from JS (untrusted events); keys are real. Games that require pointer-lock may not respond to the mouse.
