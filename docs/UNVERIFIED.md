# Not yet verified (requires a real Android device or services unavailable here)

1. **Install & launch on a physical Android phone/tablet** — not done. APK signatures verified only.
2. **Frame rate / 60 fps target** on any device — unmeasured. Quality presets and auto-resolution scaling exist but are untuned for real GPUs (Adreno / Mali / PowerVR). Shader compile stutter on first flight is mitigated by prewarm but unverified.
3. **Multi-touch stick feel**, dead zones, and simultaneous touches on real touchscreens (tested only with emulated mouse input).
4. **Audio** — synthesized sounds were generated and played through the headless/dummy driver; loudness balance, Doppler and latency on phone speakers are unheard.
5. **Thermals / battery drain / memory** on long sessions.
6. **Aspect ratios / notches / safe areas** other than 1600×740 and 1280×720-ish screenshots.
7. **AAB (Play bundle)** — not built (Gradle and Google Maven unreachable from the build environment). Preset is included.
8. **Gamepad** input mapping — implemented, untested with hardware.
9. **Android back button / app pause-resume / focus loss** — code paths exist, not exercised on device.
10. **ETC2/ASTC texture compression** output on devices — enabled, unverified.
11. **Flight model realism** — tuned against physical reasoning and scripted tests, not against real RC pilots' feedback or measured aircraft data.
12. **Play Store policies** (data safety, content rating) — drafts only.
